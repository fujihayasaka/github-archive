const dataPoints = []

const today = new Date()
const years = 3
for (let i = 0; i < 52 * years; i++) {
  // Calculate the date for the current iteration
  const date = new Date(today)
  date.setDate(date.getDate() - i * 7)
  // Subtract i weeks (7 days per week)

  const addition = Math.floor(Math.random() * 40)
  const deletion = Math.floor(Math.random() * 40)
  const commits = Math.floor(Math.random() * 40)
  dataPoints.push({w: date.getTime() / 1000, a: addition, d: deletion, c: commits})
}
dataPoints.reverse()

export default [
  {
    author: {
      id: 146,
      login: 'collaborator',
      avatar: 'http://alambic.github.localhost/avatars/u/146?s=60',
      path: '/collaborator',
      hovercard_url: '/users/collaborator/hovercard',
    },
    total: 1,
    weeks: dataPoints,
  },
  {
    author: {
      id: 2,
      login: 'monalisa',
      avatar: 'http://alambic.github.localhost/avatars/u/2?s=60',
      path: '/monalisa',
      hovercard_url: '/users/monalisa/hovercard',
    },
    total: 2,
    weeks: dataPoints,
  },
]
