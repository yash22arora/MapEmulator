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
    this.connections.add(conn);
    if (this.lastEmittedItem) {
      conn.write(`data: ${JSON.stringify(this.lastEmittedItem)}\n\n`);
    }
  }

  removeConnection(conn: Response) {
    this.connections.delete(conn);
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
          conn.write(`data: ${JSON.stringify(recentItem)}\n\n`);
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
