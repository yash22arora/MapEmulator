import express, { Request, Response } from "express";
import type { LocationUpdate } from "./types";
import { OutgoingHttpHeaders } from "node:http";
import { DummyQueue } from "./queue";
import { broadcastWorker } from "./services";

const app = express();
const PORT = 3000;
let connections: Response[] = [];
const queue = new DummyQueue<LocationUpdate>();

app.use(express.static("public"));

app.get("/stream", (req: Request, res: Response) => {
  const sseHeaders: OutgoingHttpHeaders = {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  };
  res.writeHead(200, sseHeaders);
  connections.push(res);

  // Clean up when the client disconnects
  req.on("close", () => {
    connections = connections.filter((conn) => conn !== res);
    res.end();
  });
});

app.post(
  "/location",
  express.json(),
  (req: Request<{}, {}, LocationUpdate>, res: Response) => {
    const { lat, lng, ts } = req.body;
    const locationData: LocationUpdate = { lat, lng, ts };

    queue.enqueue(locationData);

    res.status(200).send("Location data sent to clients.");
  },
);

// Start the broadcast worker to send location updates to all connected clients
broadcastWorker.start(queue, connections);

app.listen(PORT, () => {
  console.log(`Server listening on http://localhost:${PORT}`);
});
