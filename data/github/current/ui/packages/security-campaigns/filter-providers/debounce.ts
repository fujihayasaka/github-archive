export default function debounce<F extends (...args: Parameters<F>) => ReturnType<F>>(
  fn: F,
  ms: number,
): (...args: Parameters<F>) => Promise<ReturnType<F>> {
  let timer: ReturnType<typeof setTimeout> | null = null

  return function (...args: Parameters<F>): Promise<ReturnType<F>> {
    clearTimeout(timer as ReturnType<typeof setTimeout>)

    return new Promise(resolve => {
      timer = setTimeout(() => resolve(fn(...args)), ms)
    })
  }
}
