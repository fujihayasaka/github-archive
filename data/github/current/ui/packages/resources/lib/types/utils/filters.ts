type Checkbox = {
  label: string
  value: string
}

type CheckboxFilterGroup = {
  name: 'contentTypes' | 'topics'
  label: string
  checkboxes: Checkbox[]
}

export const CheckboxFilterGroups: CheckboxFilterGroup[] = [
  {
    name: 'contentTypes',
    label: 'Content Type',
    checkboxes: [
      {
        label: 'Whitepapers',
        value: 'whitepaper',
      },
      {
        label: 'Ebooks',
        value: 'ebook',
      },
    ],
  },
  {
    name: 'topics',
    label: 'Category',
    checkboxes: [
      {
        label: 'AI',
        value: 'ai',
      },
      {
        label: 'Cloud',
        value: 'cloud',
      },
      {
        label: 'DevOps',
        value: 'devops',
      },
      {
        label: 'GitHub Actions',
        value: 'github-actions',
      },
      {
        label: 'GitHub Advanced Security',
        value: 'github-advanced-security',
      },
      {
        label: 'GitHub Enterprise',
        value: 'github-enterprise',
      },
      {
        label: 'Innersource',
        value: 'innersource',
      },
      {
        label: 'Open Source',
        value: 'open-source',
      },
      {
        label: 'Security',
        value: 'security',
      },
      {
        label: 'Software Development',
        value: 'software-development',
      },
    ],
  },
]
