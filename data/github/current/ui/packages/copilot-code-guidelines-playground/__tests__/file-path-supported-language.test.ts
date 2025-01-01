import {checkIsFilePathSupportedLanguage} from '../components/file-path-supported-language'

const testPathsAndExpectedResult = {
  '.js': true,
  '*.go': true,
  '**/*.php': false,
  '**/*.test.tsx': true,
  GEMFILE: true,
  '**/*': true,
}

test('checkIsFilePathSupportedLanguage', async () => {
  for (const [path, expectedResult] of Object.entries(testPathsAndExpectedResult)) {
    expect(checkIsFilePathSupportedLanguage(path)).toBe(expectedResult)
  }
})
