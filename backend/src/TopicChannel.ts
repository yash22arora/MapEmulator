import { DummyQueue } from "./queue";
import { Response } from "express";

interface ITopicChannel<T> {
  topic: string;
  queue: DummyQueue<T>;
  connections: Set<Response>;
  lastBroadcastedItem: T | null;
  addConnection: (conn: Response) => void;
  removeConnection: (conn: Response) => void;
  start: () => void;
  stop: () => void;
}

export class TopicChannel<T> implements ITopicChannel<T> {
  topic: string;
  queue: DummyQueue<T>;
  connections: Set<Response>;
  lastBroadcastedItem: T | null;
  private started: boolean = false;
  private intervalId: NodeJS.Timeout | null = null;

  constructor(topic: string, queue: DummyQueue<T>, connections: Set<Response>) {
    this.topic = topic;
    this.queue = queue;
    this.connections = connections;
    this.lastBroadcastedItem = null;
  }

  addConnection(conn: Response) {
    this.connections.add(conn);
    if (this.lastBroadcastedItem) {
      conn.write(`data: ${JSON.stringify(this.lastBroadcastedItem)}\n\n`);
    }
  }

  removeConnection(conn: Response) {
    this.connections.delete(conn);
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
        this.lastBroadcastedItem = recentItem;
        this.connections.forEach((conn) => {
          conn.write(`data: ${JSON.stringify(recentItem)}\n\n`);
        });
        console.log(
          `Topic: ${this.topic}`,
          "Dropped:",
          this.queue.getQueueSize() - 1,
          "\t",
          "Broadcasted:",
          recentItem,
        );
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
