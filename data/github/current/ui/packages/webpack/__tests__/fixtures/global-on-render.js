export default function handleRequest() {
  globalThis.someVariable = true
  return 'This should throw an error'
}
