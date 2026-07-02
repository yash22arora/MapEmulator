import express, { Request, Response } from "express";

interface LocationUpdate {
  lat: number;
  lng: number;
}

const app = express();
const PORT = 3000;
let connections: Response[] = [];

app.use(express.static("public"));

app.get("/stream", (req: Request, res: Response) => {
  const sseHeaders = {
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
    const { lat, lng } = req.body;
    const locationData: LocationUpdate = { lat, lng };

    // Broadcast the location data to all connected clients
    connections.forEach((conn) => {
      conn.write(`data: ${JSON.stringify(locationData)}\n\n`);
    });

    res.status(200).send("Location data sent to clients.");
  },
);

app.listen(PORT, () => {
  console.log(`Server listening on http://localhost:${PORT}`);
});
