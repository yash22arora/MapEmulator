class DummyQueue<T> {
  private MAX_QUEUE_SIZE = 100;
  private queue: T[] = [];
  enqueue = (item: T) => {
    if (this.queue.length >= this.MAX_QUEUE_SIZE) {
      this.queue.shift(); // Remove the oldest item
    }
    this.queue.push(item);
  };
  empty = () => {
    this.queue = [];
  };
  getQueueSize = () => {
    return this.queue.length;
  };
  getRecentItem = () => {
    return this.queue[this.queue.length - 1];
  };

  constructor(maxQueueSize?: number) {
    if (maxQueueSize) {
      this.MAX_QUEUE_SIZE = maxQueueSize;
    }
  }
}
export { DummyQueue };
