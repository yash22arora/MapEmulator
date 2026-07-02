import { DummyQueue } from "./queue";
import { LocationUpdate } from "./types";
import { Response } from "express";

const broadCastLocation = (
  queue: DummyQueue<LocationUpdate>,
  connections: Response[],
) => {
  let recentLocation = queue.getRecentItem();
  if (recentLocation) {
    connections.forEach((conn) => {
      conn.write(`data: ${JSON.stringify(recentLocation)}\n\n`);
    });
    console.log(
      "Dropped:",
      queue.getQueueSize() - 1,
      "\t",
      "Broadcasted:",
      recentLocation,
    );
    queue.empty();
  }
};

export const broadcastWorker = {
  start: (queue: DummyQueue<LocationUpdate>, connections: Response[]) => {
    setInterval(() => {
      broadCastLocation(queue, connections);
    }, 1000); // Broadcast every second
  },
};
