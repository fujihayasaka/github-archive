export interface RecommendationDismissals {
  vscodeDismissed: boolean
  desktopDismissed: boolean
}

export type RecommendationKey = keyof RecommendationDismissals
