import { on } from 'delegated-events'

// this input contains 6 chars so we don't need to worry about throttling or waiting for blur
// eslint-disable-next-line delegated-events/no-high-freq
on('input', '.js-color-hex-input', async (event) => {
  const hexInput = event.currentTarget as HTMLInputElement
  const previewButton = hexInput.parentElement!.querySelector(
    '.js-color-preview-button',
  ) as HTMLButtonElement

  if (previewButton) {
    setPreviewColor(previewButton, hexInput.value)
  }
})

on('click', '.js-color-preview-button', async (event) => {
  const previewButton = event.currentTarget as HTMLInputElement
  const hexInput = previewButton.parentElement!.querySelector(
    '.js-color-hex-input',
  ) as HTMLInputElement

  if (hexInput) {
    const hex = [
      Math.floor(Math.random() * (255 - 0) + 0),
      Math.floor(Math.random() * (255 - 0) + 0),
      Math.floor(Math.random() * (255 - 0) + 0),
    ]
      .map((number) => number.toString(16).padStart(2, '0'))
      .join('')

    hexInput.value = hex
    setPreviewColor(previewButton, hex)
  }
})

function setPreviewColor(previewButton, hex) {
  const r = parseInt(hex.substring(0, 2), 16)
  const g = parseInt(hex.substring(2, 4), 16)
  const b = parseInt(hex.substring(4, 6), 16)
  // close enough preview approximation of the LabelComponent#text_color logic
  const font = r * 0.299 + g * 0.587 + b * 0.114 > 186 ? 'black' : 'white'
  previewButton.setAttribute(
    'style',
    `background-color: #${hex}; color: ${font}`,
  )
}
