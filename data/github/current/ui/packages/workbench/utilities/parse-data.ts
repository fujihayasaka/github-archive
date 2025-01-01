export type JSONValue = string | number | boolean | null | JSONObject | JSONArray

export type JSONArray = JSONValue[]
export type JSONObject = {[key: string]: JSONValue}

export type JSONTableObject = JSONObject & {id: string | number} // JSON objects in a table must have an 'id' field for unique identification
export type JSONTable = JSONTableObject[]

export type DataString = {
  type: 'string'
  data: string
}
export type DataTable = {
  type: 'table'
  data: JSONTable
  allKeys: string[]
}
export type DataArray = {
  type: 'array'
  data: JSONArray
}
export type DataObject = {
  type: 'object'
  data: JSONObject
}
export type DataNumber = {
  type: 'number'
  data: number
}
export type DataType = DataString | DataObject | DataNumber | DataArray | DataTable

export const parseData = (value: string | number): DataType => {
  if (typeof value === 'number') return {data: value, type: 'number'} satisfies DataNumber
  try {
    const parsedValue = JSON.parse(value)
    if (typeof parsedValue === 'number') {
      return {data: parsedValue, type: 'number'} satisfies DataNumber
    }

    // Check if the item is an array
    if (Array.isArray(parsedValue)) {
      // If it's an array of objects (and actually has some structure to it by at least containing a single object),
      // then we call it a "table"
      if (parsedValue.length > 0 && parsedValue.every(item => typeof item === 'object')) {
        const dataValuesWithId = parsedValue.map(dataValue => ({
          ...dataValue,
          id: dataValue.id ?? crypto.randomUUID().substring(0, 8), // Ensure each item has a unique identifier
        })) satisfies JSONTable
        return {
          data: dataValuesWithId,
          type: 'table',
          allKeys: dataValuesWithId.reduce((acc, item) => {
            const keys = Object.keys(item)
            for (const key of keys) {
              if (!acc.includes(key)) {
                acc.push(key)
              }
            }
            return acc
          }, [] as string[]),
        } satisfies DataTable
      }

      // else it's a primitives array (or contains a primitive), and not a table
      return {data: parsedValue, type: 'array'} satisfies DataArray
    }

    // It could just be a serialized object, which we can support.
    if (typeof parsedValue === 'object') {
      return {data: parsedValue, type: 'object'} satisfies DataObject
    }

    // Let's just call it a string
    return {data: parsedValue, type: 'string'} satisfies DataString
  } catch {
    return {data: value, type: 'string'} satisfies DataString
  }
}

export type DatabaseMock = {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  [key: string]: any
}

export const DATABASE_DEFAULT: DatabaseMock = {
  keyString: 'some value',
  keyNumber: 42,
  keyBoolean: true,
  keySimpleObject: {
    keyA: 'nested value',
    keyB: 24,
    keyC: false,
  },
  keySimpleArray: ['a', 'b', 'c', 'd'],
  keySimpleTableArray: [...Array(10).keys()].map(i => ({
    keyA: `Object ${i + 1}`,
    keyB: i + 10,
    keyC: `${'a'.charCodeAt(0) + i}`,
  })),
  keyNestedObject: {
    keyA: 'valueA',
    keyB: 10,
    keyC: {
      nestedKeyA: 'nestedValueA',
      nestedKeyB: 20,
    },
    keyD: {
      nestedKeyA: 'nestedValueA',
      nestedKeyB: {
        doubleNestedKeyA: 'doubleNestedValueA',
        doubleNestedKeyB: 30,
      },
    },
  },
  keyComplexTableArray: [...Array(20).keys()].map(i => ({
    keyA: `Object ${i + 1}`,
    keyB: i + 10,
    keyC: `${'a'.charCodeAt(0) + i}`,
    keyD: {
      nestedKeyA: `nestedValueA-${i}`,
      nestedKeyB: i * 2,
      nestedKeyC: {
        doubleNestedKeyA: `doubleNestedValueA-${i}`,
        doubleNestedKeyB: i * 3,
      },
    },
    keyE: i % 2 === 0 ? true : undefined,
  })),
}
