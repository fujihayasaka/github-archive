// IMPORTANT: Since tests run in parallel, you should always await this function
//            otherwise it will affect other tests.
export const withDisabledCharacterKeys = async (testFn: () => Promise<void>) => {
  const meta = document.createElement('meta')
  meta.name = 'keyboard-shortcuts-preference'
  meta.content = 'no_character_key'
  document.head.appendChild(meta)

  await testFn()

  meta.remove()
}
