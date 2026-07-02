const express = require("express");

const app = express();
const PORT = 3000;

app.use(express.static("public"));

app.get("/stream", (req, res) => {
  const sseHeaders = {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  };
  res.writeHead(200, sseHeaders);

  const sendEvent = (data) => {
    res.write(`data: ${JSON.stringify(data)}\n\n`);
  };

  // Simulate sending events every second
  const intervalId = setInterval(() => {
    const eventData = {
      lat: 37.7749 + Math.random() * 0.01, // Random latitude near San Francisco
      lng: -122.4194 + Math.random() * 0.01, // Random longitude near San Francisco
      timestamp: new Date(),
    };
    sendEvent(eventData);
  }, 1000);

  // Clean up when the client disconnects
  req.on("close", () => {
    clearInterval(intervalId);
    console.log("Client disconnected");
    res.end();
  });
});

app.listen(PORT, () => {
  console.log(`Server listening on http://localhost:${PORT}`);
});
