export const wait = (ms: number): Promise<NodeJS.Timeout> =>
  new Promise(resolve => {
    const timeoutRef = setTimeout(() => resolve(timeoutRef), ms)
  })
