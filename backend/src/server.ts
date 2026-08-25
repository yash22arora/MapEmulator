import express, { Request, Response } from "express";
import type { LocationUpdate } from "./types";
import { OutgoingHttpHeaders } from "node:http";
import { DummyQueue } from "./queue";
import { getOrCreateTopicChannel } from "./services";
const app = express();
const PORT = 3000;

app.use(express.static("public"));

app.get("/location/stream", (req: Request, res: Response) => {
  const topic = req.query.topic;
  if (!topic || typeof topic !== "string") {
    res.status(400).send("Topic query parameter is required.");
    return;
  }

  const topicChannel = getOrCreateTopicChannel(topic);

  const sseHeaders: OutgoingHttpHeaders = {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  };
  res.writeHead(200, sseHeaders);
  topicChannel.addConnection(res);
  topicChannel.start(); // Start broadcasting if not already started

  // Clean up when the client disconnects
  req.on("close", () => {
    topicChannel.removeConnection(res);
    res.end();
  });
});

app.post(
  "/location",
  express.json(),
  (req: Request<{}, {}, LocationUpdate>, res: Response) => {
    const { topic, lat, lng, ts } = req.body;
    if (!topic || lat === undefined || lng === undefined || ts === undefined) {
      res.status(400).send("Missing required fields: topic, lat, lng, ts.");
      return;
    }
    const locationData: LocationUpdate = { topic, lat, lng, ts };
    let topicChannel = getOrCreateTopicChannel(topic);
    topicChannel.pushEvent(locationData);

    res.status(200).send("Location data sent to clients.");
  },
);

app.post(
  "/location/complete",
  express.json(),
  (req: Request<{}, {}, { topic: string }>, res: Response) => {
    const { topic } = req.body;
    if (!topic) {
      res.status(400).send("Missing required field: topic.");
      return;
    }
    let topicChannel = getOrCreateTopicChannel(topic);
    topicChannel.markAsCompleted();

    res.status(200).send("Marked as completed and notified all clients.");
  },
);

app.listen(PORT, () => {
  console.log(`Server listening on http://localhost:${PORT}`);
});
