// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
export interface FeaturesItem {
  title: string
  description: string
  availability: Array<string | boolean>
}

export interface FeaturesTableProps {
  title: string
  tiers: string[]
  features: FeaturesItem[]
  aria: {
    included: string
    notIncluded: string
  }
}
