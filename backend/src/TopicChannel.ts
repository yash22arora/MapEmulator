import { DummyQueue } from "./queue";
import { Response } from "express";
import { StatusType } from "./types";

interface ITopicChannel<T extends { ts: number }> {
  topic: string;
  connections: Set<Response>;
  lastEmittedItem: T | null;
  addConnection: (conn: Response) => void;
  removeConnection: (conn: Response) => void;
  pushEvent: (item: T) => void;
  start: () => void;
  stop: () => void;
  updateStatus: (status: StatusType) => void;
  markAsCompleted: () => void;
}

export class TopicChannel<
  T extends { ts: number },
> implements ITopicChannel<T> {
  topic: string;
  private queue: DummyQueue<T>;
  connections: Set<Response>;
  lastEmittedItem: T | null;
  private started: boolean = false;
  private intervalId: NodeJS.Timeout | null = null;
  private isCompleted: boolean = false;
  // pendingConfirmation is the natural starting point for a freshly
  // created topic -- an order that's never been touched is, by
  // definition, awaiting confirmation.
  private lastStatus: StatusType = "pendingConfirmation";

  private COMPLETED_FRAME = "event: completed\ndata: {}\n\n";

  constructor(topic: string, queue: DummyQueue<T>, connections: Set<Response>) {
    this.topic = topic;
    this.queue = queue;
    this.connections = connections;
    this.lastEmittedItem = null;
  }

  addConnection(conn: Response) {
    // Response is a writable stream -- it can emit 'error' at any time
    // (e.g. ECONNRESET if the client force-quits), and an unhandled
    // 'error' event crashes the whole Node process, not just this request.
    conn.on("error", (error) => {
      console.error(
        `Connection error on topic ${this.topic}, removing:`,
        error,
      );
      this.removeConnection(conn);
    });

    this.connections.add(conn);

    if (this.isCompleted) {
      // A client connecting to an already-completed topic (e.g. reopening
      // tracking after delivery) should see that immediately, not a stale
      // in-progress status followed by silence. Also matches the "don't
      // relay/save rider location once delivered" requirement -- we never
      // reach the location-replay logic below.
      this.writeRaw(conn, this.COMPLETED_FRAME);
      return;
    }

    // The broadcast interval (start()/stop()) only runs while at least one
    // connection is open, so a location posted while the topic was idle
    // (zero connections) never gets promoted into lastEmittedItem -- it's
    // just sitting in the queue, unbroadcast. Only drain it here on the
    // connection that brings the topic from 0 -> 1: if others are already
    // connected, the interval is already running for them, and draining
    // the queue early would steal an item out from under its next tick
    // before it gets a chance to broadcast it to those existing clients.
    if (this.connections.size === 1) {
      const recentItem = this.queue.getRecentItem();
      if (recentItem) {
        this.lastEmittedItem = recentItem;
        this.queue.empty();
      }
    }

    this.writeStatus(conn, this.lastStatus);
    if (this.lastEmittedItem) {
      this.writeToConnection(conn, this.lastEmittedItem);
    }
  }

  removeConnection(conn: Response) {
    this.connections.delete(conn);
    if (this.connections.size === 0) {
      this.stop();
    }
  }

  private writeToConnection(conn: Response, item: T) {
    const frame = `data: ${JSON.stringify(item)}\n\n`;
    this.writeRaw(conn, frame);
  }

  private writeRaw(conn: Response, frame: string) {
    try {
      conn.write(frame);
    } catch (error) {
      console.error(
        `Failed to write raw frame to a connection on topic ${this.topic}, removing it:`,
        error,
      );
      this.removeConnection(conn);
    }
  }

  private writeStatus(conn: Response, status: StatusType) {
    this.writeRaw(conn, `event: status\ndata: ${JSON.stringify({ status })}\n\n`);
  }

  pushEvent(item: T) {
    if (this.isCompleted) {
      return;
    } // Ignore new events if the topic is marked as completed
    this.queue.enqueue(item);
  }

  // "delivered" is handled by markAsCompleted (terminal: closes the
  // connections and stops broadcasting) rather than as a plain status
  // frame, since a plain data:/status frame can't express "the stream is
  // ending" -- see Phase 13/14. Every other status is a routine,
  // non-terminal update.
  updateStatus(status: StatusType) {
    if (this.isCompleted) {
      return;
    }
    if (status === "delivered") {
      this.markAsCompleted();
      return;
    }

    this.lastStatus = status;
    this.connections.forEach((conn) => {
      this.writeStatus(conn, status);
    });
  }

  markAsCompleted() {
    this.isCompleted = true;
    this.queue.empty(); // Clear the queue since no more events will be sent
    this.lastEmittedItem = null; // Nothing left to relay/cache once delivered
    this.connections.forEach((conn) => {
      this.writeRaw(conn, this.COMPLETED_FRAME);
      conn.end(); // Close the connection after sending the completed frame
    });
    this.stop(); // Stop broadcasting since the topic is completed
  }

  start() {
    if (this.started) {
      console.log(`TopicChannel for ${this.topic} is already started.`);
      return;
    }

    this.started = true;
    this.intervalId = setInterval(() => {
      const recentItem = this.queue.getRecentItem();
      if (recentItem) {
        this.lastEmittedItem = recentItem;
        this.connections.forEach((conn) => {
          this.writeToConnection(conn, recentItem);
        });
        console.log(`Topic: ${this.topic}`, "\t", "Broadcasted:", recentItem);
        this.queue.empty();
      }
    }, 1000); // Broadcast every second
  }

  stop: () => void = () => {
    this.started = false;
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
  };
}
