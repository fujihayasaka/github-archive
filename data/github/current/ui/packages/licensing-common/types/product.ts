export const Product = {
  GHEC: 'Enterprise Cloud',
  GHAS: 'Advanced Security',
} as const

export type Product = (typeof Product)[keyof typeof Product]
