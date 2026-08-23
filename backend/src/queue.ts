class DummyQueue<T extends { ts: number }> {
  private lastItem: T | null = null;
  enqueue = (item: T) => {
    if (!this.lastItem || item.ts > this.lastItem.ts) {
      // timestamp check to ignore older items arriving late due to network issues
      this.lastItem = item;
    }
  };
  empty = () => {
    this.lastItem = null;
  };
  getRecentItem = () => {
    return this.lastItem;
  };
}
export { DummyQueue };
