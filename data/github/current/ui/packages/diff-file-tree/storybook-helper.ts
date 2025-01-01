// Disable role=presentation axe rule on anchor tag - see https://github.com/github/pull-requests/issues/14822#issuecomment-2492067858
export const DiffFileTreeAxeRules = [
  {id: 'aria-allowed-role', selector: 'li[role="treeitem"] a)', enabled: false},
  {
    id: 'presentation-role-conflict',
    selector: 'ul[role="tree"], li[role="treeitem"], li[role="treeitem"] a',
    enabled: false,
  },
]
