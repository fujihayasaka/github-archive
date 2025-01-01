// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type {ImageDimensions} from './types'

const PNG_HEADER = 0x89504e47
const CRC_WIDTH = 4

export class PNGScanner {
  dataview: DataView
  pos: number
  callback: ((dimensions: ImageDimensions) => void) | undefined

  constructor(buffer: ArrayBuffer, callback?: (dimensions: ImageDimensions) => void) {
    this.dataview = new DataView(buffer)
    this.pos = 0
    this.callback = callback
  }

  advance(bytes: number) {
    this.pos += bytes
  }

  readInt(bytes: 1 | 2 | 4) {
    /* eslint-disable-next-line @typescript-eslint/no-this-alias */
    const self = this

    // I want the do { } syntax *so* bad.
    const value = (function () {
      switch (bytes) {
        case 1:
          return self.dataview.getUint8(self.pos)
        case 2:
          return self.dataview.getUint16(self.pos)
        case 4:
          return self.dataview.getUint32(self.pos)
        default:
          // I shouldn't need this, but flow can't figure out that all values of bytes are handled by the above switch
          throw new Error('bytes parameter must be 1, 2 or 4')
      }
    })()
    this.advance(bytes)
    return value
  }

  readChar() {
    return this.readInt(1)
  }

  readShort() {
    return this.readInt(2)
  }

  readLong() {
    return this.readInt(4)
  }

  readString(length: number): string {
    const buf = []
    for (let i = 0; i < length; i++) {
      buf.push(String.fromCharCode(this.readChar()))
    }
    return buf.join('')
  }

  scan(fn: (this: PNGScanner, type: string, len: number) => boolean) {
    if (this.readLong() !== PNG_HEADER) {
      throw new Error('invalid PNG')
    }

    this.advance(4)

    for (;;) {
      const len = this.readLong()
      const type = this.readString(4)
      const resumeAt = this.pos + len + CRC_WIDTH
      if (fn.call(this, type, len) === false || type === 'IEND') {
        break
      }
      this.pos = resumeAt
    }
  }
}
