const express = require("express");

const app = express();
const PORT = 3000;
let connections = [];

app.use(express.static("public"));

app.get("/stream", (req, res) => {
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

app.post("/location", express.json(), (req, res) => {
  const { lat, lng } = req.body;
  const locationData = { lat, lng };

  // Broadcast the location data to all connected clients
  connections.forEach((conn) => {
    conn.write(`data: ${JSON.stringify(locationData)}\n\n`);
  });

  res.status(200).send("Location data sent to clients.");
});

app.listen(PORT, () => {
  console.log(`Server listening on http://localhost:${PORT}`);
});
