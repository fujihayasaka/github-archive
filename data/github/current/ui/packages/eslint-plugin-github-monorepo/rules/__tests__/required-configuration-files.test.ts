import rule from '../required-configuration-files'

jest.mock('fs', () => ({
  existsSync: jest.fn(),
  readFileSync: jest.fn(),
  writeFileSync: jest.fn(),
  unlinkSync: jest.fn(),
}))

const mockRuleInvoke = () => {
  const mockContext = {
    report: jest.fn(),
    getPhysicalFilename: jest.fn(() => '/path/to/package/index.js'),
  }
  const caller = rule.create(mockContext)['Program:exit']

  return {
    context: mockContext,
    call: caller,
  }
}

const mockExistsSync = (files: Record<string, boolean>) => {
  ;(jest.requireMock('fs').existsSync as jest.Mock).mockImplementation((filePath: string) => {
    return files[filePath] || false
  })
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const mockReadFileSync = (packageJsonContent: Record<string, any>) => {
  ;(jest.requireMock('fs').readFileSync as jest.Mock).mockImplementation((filePath: string) => {
    if (filePath.endsWith('package.json')) {
      return JSON.stringify(packageJsonContent)
    }
    if (filePath.endsWith('tsconfig.json.hbs')) {
      return 'TS configuration template content'
    }
    if (filePath.endsWith('jest.config.js.hbs')) {
      return 'Jest configuration template content'
    }
    return ''
  })
}

describe('required-configuration-files rule', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('reports an error and fixes it when tsconfig.json is missing', () => {
    const mockWriteFileSync = jest.requireMock('fs').writeFileSync as jest.Mock

    mockExistsSync({
      '/path/to/package/jest.config.js': true,
      '/path/to/package/tsconfig.json': false,
    })
    mockReadFileSync({})

    const {context, call} = mockRuleInvoke()

    call()

    expect(context.report).toHaveBeenCalledTimes(1)
    expect(context.report).toHaveBeenCalledWith(
      expect.objectContaining({
        messageId: 'missingFile',
        data: {file: 'tsconfig.json'},
        fix: expect.any(Function),
      }),
    )

    const fixFunction = context.report.mock.calls[0][0].fix
    fixFunction()

    expect(mockWriteFileSync).toHaveBeenCalledWith(
      expect.stringContaining('tsconfig.json'),
      'TS configuration template content',
    )
  })

  describe('when package.json does not import @github-ui/tests', () => {
    it('does not report an error when required files are present', () => {
      mockExistsSync({
        '/path/to/package/tsconfig.json': true,
        '/path/to/package/jest.config.js': true,
      })
      mockReadFileSync({
        scripts: {
          test: 'jest',
        },
        devDependencies: {
          '@github-ui/jest': '*',
        },
      })

      const {context, call} = mockRuleInvoke()

      call()

      expect(context.report).toHaveBeenCalledTimes(0)
    })

    it('reports an error and fixes it when jest.config.js is missing', () => {
      const mockWriteFileSync = jest.requireMock('fs').writeFileSync as jest.Mock

      mockExistsSync({
        '/path/to/package/jest.config.js': false,
        '/path/to/package/tsconfig.json': true,
      })
      mockReadFileSync({
        scripts: {
          test: 'jest',
        },
        devDependencies: {
          '@github-ui/jest': '*',
        },
      })

      const {context, call} = mockRuleInvoke()

      call()

      expect(context.report).toHaveBeenCalledTimes(1)
      expect(context.report).toHaveBeenCalledWith(
        expect.objectContaining({
          messageId: 'missingFile',
          data: {file: 'jest.config.js'},
          fix: expect.any(Function),
        }),
      )

      const fixFunction = context.report.mock.calls[0][0].fix
      fixFunction()

      expect(mockWriteFileSync).toHaveBeenCalledWith(
        expect.stringContaining('jest.config.js'),
        'Jest configuration template content',
      )
    })
    it('reports an error and fixes it when jest.config.js and tsconfig.json are missing', () => {
      const mockWriteFileSync = jest.requireMock('fs').writeFileSync as jest.Mock

      mockExistsSync({
        '/path/to/package/jest.config.js': false,
        '/path/to/package/tsconfig.json': false,
      })
      mockReadFileSync({
        scripts: {
          test: 'jest',
        },
        devDependencies: {
          '@github-ui/jest': '*',
        },
      })

      const {context, call} = mockRuleInvoke()

      call()

      expect(context.report).toHaveBeenCalledTimes(2)
      expect(context.report).toHaveBeenCalledWith(
        expect.objectContaining({
          messageId: 'missingFile',
          data: {file: 'jest.config.js'},
          fix: expect.any(Function),
        }),
      )
      expect(context.report).toHaveBeenCalledWith(
        expect.objectContaining({
          messageId: 'missingFile',
          data: {file: 'tsconfig.json'},
          fix: expect.any(Function),
        }),
      )

      const fixFunction1 = context.report.mock.calls[0][0].fix
      const fixFunction2 = context.report.mock.calls[1][0].fix
      fixFunction1()
      fixFunction2()

      expect(mockWriteFileSync).toHaveBeenCalledTimes(2)

      expect(mockWriteFileSync).toHaveBeenNthCalledWith(
        1,
        expect.stringContaining('tsconfig.json'),
        'TS configuration template content',
      )

      expect(mockWriteFileSync).toHaveBeenNthCalledWith(
        2,
        expect.stringContaining('jest.config.js'),
        'Jest configuration template content',
      )
    })
  })

  describe('when package.json imports @github-ui/tests', () => {
    it('does not report an error when scripts includes test: ui-test and jest.config.js is missing', () => {
      mockExistsSync({
        '/path/to/package/tsconfig.json': true,
        '/path/to/package/package.json': true,
      })
      mockReadFileSync({
        scripts: {
          test: 'ui-test',
        },
        devDependencies: {
          '@github-ui/tests': '*',
        },
      })

      const {context, call} = mockRuleInvoke()

      call()

      expect(context.report).toHaveBeenCalledTimes(0)
    })

    it('does not report an error when scripts includes test: jest and jest.config.js is present', () => {
      mockExistsSync({
        '/path/to/package/tsconfig.json': true,
        '/path/to/package/jest.config.js': true,
        '/path/to/package/package.json': true,
      })
      mockReadFileSync({
        scripts: {
          test: 'jest',
        },
        devDependencies: {
          '@github-ui/tests': '*',
        },
      })

      const {context, call} = mockRuleInvoke()

      call()

      expect(context.report).toHaveBeenCalledTimes(0)
    })

    it('reports an error and fixes it when scripts includes test: ui-test and jest.config.js is present', () => {
      const mockUnlinkSync = jest.requireMock('fs').unlinkSync as jest.Mock

      mockExistsSync({
        '/path/to/package/tsconfig.json': true,
        '/path/to/package/jest.config.js': true,
        '/path/to/package/package.json': true,
      })
      mockReadFileSync({
        scripts: {
          test: 'ui-test',
        },
        devDependencies: {
          '@github-ui/tests': '*',
        },
      })

      const {context, call} = mockRuleInvoke()

      call()

      expect(context.report).toHaveBeenCalledTimes(1)
      expect(context.report).toHaveBeenCalledWith(
        expect.objectContaining({
          messageId: 'unnecessaryFile',
          data: {file: 'jest.config.js'},
          fix: expect.any(Function),
        }),
      )

      const fixFunction = context.report.mock.calls[0][0].fix
      fixFunction()

      expect(mockUnlinkSync).toHaveBeenCalledWith(expect.stringContaining('jest.config.js'))
    })
    it('reports an error and fixes it when scripts includes test: jest and jest.config.js is missing', () => {
      const mockWriteFileSync = jest.requireMock('fs').writeFileSync as jest.Mock

      mockExistsSync({
        '/path/to/package/tsconfig.json': true,
        '/path/to/package/jest.config.js': false,
        '/path/to/package/package.json': true,
      })
      mockReadFileSync({
        scripts: {
          test: 'jest',
        },
        devDependencies: {
          '@github-ui/tests': '*',
        },
      })

      const {context, call} = mockRuleInvoke()

      call()

      expect(context.report).toHaveBeenCalledTimes(1)
      expect(context.report).toHaveBeenCalledWith(
        expect.objectContaining({
          messageId: 'missingFile',
          data: {file: 'jest.config.js'},
          fix: expect.any(Function),
        }),
      )

      const fixFunction = context.report.mock.calls[0][0].fix
      fixFunction()

      expect(mockWriteFileSync).toHaveBeenCalledWith(
        expect.stringContaining('jest.config.js'),
        'Jest configuration template content',
      )
    })
  })
})
