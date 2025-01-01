export const CampaignDialogTabs = {
  General: 'general',
  Filters: 'filters',
  Repositories: 'repositories',
}

export const CampaignDialogTabContentHeight = 500

export type CampaignDialogTab = (typeof CampaignDialogTabs)[keyof typeof CampaignDialogTabs]
