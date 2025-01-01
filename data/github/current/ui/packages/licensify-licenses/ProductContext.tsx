import type {PropsWithChildren} from 'react'
import {createContext, useContext} from 'react'

const ProductContext = createContext<string | null>(null)

export function ProductProvider({children, product}: PropsWithChildren<{product: string}>) {
  return <ProductContext.Provider value={product}>{children}</ProductContext.Provider>
}

export function useProduct() {
  const context = useContext(ProductContext)

  if (!context) {
    throw new Error('useProduct must be used within a ProductProvider.')
  }

  return context
}
