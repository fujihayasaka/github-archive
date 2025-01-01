let virtualPriority = 0.1
const step = 0.00000001

function setValue(n: number) {
  virtualPriority = n
}

export function getNextPriority(): string {
  const newValue = virtualPriority - step
  setValue(newValue)
  return `${newValue}`
}
