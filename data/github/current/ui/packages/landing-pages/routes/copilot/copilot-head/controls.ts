class Controls {
  params: {clickAction: string; blinkingSpeed: number}
  frequences: string[]
  constructor() {
    this.params = {
      clickAction: 'random',
      blinkingSpeed: 2,
    }

    this.frequences = ['jump1', 'jump1', 'jump3', 'jump3', 'wink', 'wink', 'shake', 'shake']
  }

  getRandomAnim(isBlinking: boolean) {
    const index = Math.floor(Math.random() * this.frequences.length)
    let name = this.frequences[index]

    if (isBlinking && name === 'wink') {
      name = 'jamp1'
    }

    return name
  }

  init() {}
}

const controls = new Controls()
export default controls
