import { DummyQueue } from "./queue";
import { Response } from "express";

interface ITopicChannel<T extends { ts: number }> {
  topic: string;
  connections: Set<Response>;
  lastEmittedItem: T | null;
  addConnection: (conn: Response) => void;
  removeConnection: (conn: Response) => void;
  pushEvent: (item: T) => void;
  start: () => void;
  stop: () => void;
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
      console.error(`Connection error on topic ${this.topic}, removing:`, error);
      this.removeConnection(conn);
    });

    this.connections.add(conn);
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
    try {
      conn.write(`data: ${JSON.stringify(item)}\n\n`);
    } catch (error) {
      console.error(`Failed to write to a connection on topic ${this.topic}, removing it:`, error);
      this.removeConnection(conn);
    }
  }

  pushEvent(item: T) {
    this.queue.enqueue(item);
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
