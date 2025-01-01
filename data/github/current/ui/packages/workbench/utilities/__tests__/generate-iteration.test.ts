import {FileStreamEventType, FileStreamParser} from '../generate-iteration'

describe('FileStreamParser', () => {
  let parser: FileStreamParser
  let onEventMock: jest.Mock

  beforeEach(() => {
    parser = new FileStreamParser()
    onEventMock = jest.fn()
  })

  it('should emit NEW_FILE and FILE_CONTENT_CHUNK events for valid file content', () => {
    const chunk = '<<—[file1.txt]\nHello, World!\n—>>\n'
    parser.processChunk(chunk, onEventMock)
    parser.finalize(onEventMock)

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.NEW_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'file1.txt',
      chunk: 'Hello, World!\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.END_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [{fileName: 'file1.txt', content: 'Hello, World!'}],
    })
  })

  it('should handle multiple files in a single chunk', () => {
    const chunk = '<<—[file1.txt]\nContent1\n—>>\n<<—[file2.txt]\nContent2\n—>>\n'
    parser.processChunk(chunk, onEventMock)
    parser.finalize(onEventMock)

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.NEW_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'file1.txt',
      chunk: 'Content1\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.END_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.NEW_FILE,
      fileName: 'file2.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'file2.txt',
      chunk: 'Content2\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.END_FILE,
      fileName: 'file2.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [
        {fileName: 'file1.txt', content: 'Content1'},
        {fileName: 'file2.txt', content: 'Content2'},
      ],
    })
  })

  it('should handle incomplete chunks and finalize correctly', () => {
    parser.processChunk('<<—[file1.txt]\nPartial content', onEventMock)
    parser.processChunk(' continued\n—>>\n', onEventMock)
    parser.finalize(onEventMock)

    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.NEW_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.FILE_CONTENT_CHUNK,
      fileName: 'file1.txt',
      chunk: 'Partial content continued\n',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.END_FILE,
      fileName: 'file1.txt',
    })
    expect(onEventMock).toHaveBeenCalledWith({
      type: FileStreamEventType.COMPLETE,
      files: [{fileName: 'file1.txt', content: 'Partial content continued'}],
    })
  })
})
