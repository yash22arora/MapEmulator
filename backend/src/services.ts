import { DummyQueue } from "./queue";
import { TopicChannel } from "./TopicChannel";
import { LocationUpdate } from "./types";
import { Response } from "express";

export const registry = new Map<string, TopicChannel<LocationUpdate>>();

export const getOrCreateTopicChannel = (
  topic: string,
): TopicChannel<LocationUpdate> => {
  if (!registry.has(topic)) {
    const queue = new DummyQueue<LocationUpdate>();
    const connections = new Set<Response>();
    const topicChannel = new TopicChannel<LocationUpdate>(
      topic,
      queue,
      connections,
    );
    registry.set(topic, topicChannel);
  }
  return registry.get(topic)!;
};
