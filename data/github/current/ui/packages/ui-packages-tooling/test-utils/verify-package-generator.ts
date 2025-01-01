import {expect, vi} from '@github-ui/tests'
import {Volume} from 'memfs'
import nodePlop from 'node-plop'
import {readdir, readFile, stat} from 'node:fs/promises'
import {tmpdir} from 'node:os'
import {dirname, relative, resolve} from 'node:path'

// Helper to recursively get all file contents in a directory
async function getFileTree(directory: string): Promise<Record<string, string>> {
  const files: Record<string, string> = {}

  async function walk(currentPath: string) {
    for (const entry of await readdir(currentPath)) {
      const fullPath = resolve(currentPath, entry)
      const relPath = relative(directory, fullPath)

      if ((await stat(fullPath)).isDirectory()) {
        await walk(fullPath)
      } else {
        files[relPath] = await readFile(fullPath, 'utf-8')
      }
    }
  }

  await walk(directory)
  return files
}

const templatesPath = resolve(__dirname, '../templates')
const projectRootPath = resolve(__dirname, '../..')
const serviceOwnersPath = resolve(projectRootPath, '../../SERVICEOWNERS')
const fixturesPath = resolve(__dirname, '../__fixtures__')
const destination = resolve(tmpdir(), './plop-test-output')

const plop = await nodePlop(resolve(__dirname, '../plopfile.ts'), {
  force: true,
  destBasePath: resolve(destination, './x'),
})

// Helper to recursively copy actual files to the virtual fs
async function copyToVirtualFS(vol: Volume, sourcePath: string, targetPath: string) {
  const entries = await readdir(sourcePath)

  for (const entry of entries) {
    const sourceEntryPath = resolve(sourcePath, entry)
    const targetEntryPath = resolve(targetPath, entry)
    const stats = await stat(sourceEntryPath)

    if (stats.isDirectory()) {
      vol.mkdirSync(targetEntryPath, {recursive: true})
      await copyToVirtualFS(vol, sourceEntryPath, targetEntryPath)
    } else {
      const content = await readFile(sourceEntryPath)
      vol.writeFileSync(targetEntryPath, content)
    }
  }
}

export async function verifyPackageGenerator({
  name,
  answers,
  fixture,
}: {
  name: string
  answers: Record<string, string | boolean>
  fixture: string
}) {
  const packageName = answers.packageName as string
  const fixturePath = resolve(__dirname, `../__fixtures__/${fixture}`)

  // Create a virtual file system
  const vol = new Volume()

  // Set up directories in the virtual fs
  vol.mkdirSync(destination, {recursive: true})
  vol.mkdirSync(templatesPath, {recursive: true})
  vol.mkdirSync(fixturesPath, {recursive: true})
  vol.mkdirSync(dirname(serviceOwnersPath), {recursive: true})

  // Copy real files to virtual fs
  await Promise.all([
    copyToVirtualFS(vol, templatesPath, templatesPath),
    copyToVirtualFS(vol, fixturesPath, fixturesPath),
  ])

  // Copy SERVICEOWNERS file
  const serviceOwnersContent = await readFile(serviceOwnersPath)
  vol.writeFileSync(serviceOwnersPath, serviceOwnersContent)

  // Setup fs mocking
  vi.doMock('fs', async () => {
    const _memfs = await import('memfs')
    return {
      ..._memfs.fs,
      promises: _memfs.fs.promises,
    }
  })

  try {
    const generator = plop.getGenerator(name)
    const {failures} = await generator.runActions(answers)
    expect(failures).toEqual([])

    const [results, expectedResults] = await Promise.all([
      getFileTree(`${destination}/${packageName}`),
      getFileTree(fixturePath),
    ])

    expect(results).toEqual(expectedResults)
  } finally {
    // Restore original fs
    vi.clearAllMocks()
  }
}
