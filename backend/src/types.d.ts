export interface LocationUpdate {
  topic: string;
  lat: number;
  lng: number;
  ts: number;
}

export type StatusType =
  | "pendingConfirmation"
  | "restaurantPreparingOrder"
  | "riderReachingRestaurant"
  | "riderPickedOrder"
  | "delivered";
