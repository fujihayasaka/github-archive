import {randomInt} from '../random-int'
import {wait} from '../wait'

const runTests = (max: number, min: number | undefined, testName: string) => {
  // eslint-disable-next-line jest/valid-title
  describe(testName, () => {
    let i = 0
    while (++i < 5) {
      it(`should generate random boolean attempt#${i}`, async () => {
        let iterations = 100
        while (iterations-- > 0) {
          const int = randomInt(max, min)

          expect(int).toBeLessThanOrEqual(max)
          expect(int).toBeGreaterThanOrEqual(min ?? 0)

          await wait(1)
        }
      })
    }

    it(`should include min and max`, async () => {
      let iterations = 100
      const results = []
      while (iterations-- > 0) {
        results.push(randomInt(max, min))
        await wait(1)
      }

      expect(results.includes(max)).toBe(true)
      expect(results.includes(min ?? 0)).toBe(true)
    })
  })
}

describe('randomInt', () => {
  describe('positive numbers', () => {
    runTests(5, 2, 'max: 5, min: 2')
    runTests(5, 0, 'max: 5, min: 0')
    runTests(5, undefined, 'max: 5, min: undefined')
    runTests(1, 0, 'max: 0, min: 0')
  })

  describe('negative numbers', () => {
    runTests(-2, -5, 'max: -2, min: -5')
    runTests(0, -5, 'max: 0, min: -5')
    runTests(0, -1, 'max: 0, min: -1')
  })

  describe('split numbers', () => {
    runTests(3, -1, 'max: 3, min: -1')
    runTests(2, -2, 'max: 2, min: -2')
    runTests(1, -3, 'max: 2, min: -2')
  })

  describe('errors', () => {
    it('should throw if "min" is == "max" #1', () => {
      expect(() => {
        randomInt(200, 200)
      }).toThrowErrorMatchingInlineSnapshot(`""max"(200) param should be greater than "min"(200)."`)
    })

    it('should throw if "min" is == "max" #2', () => {
      expect(() => {
        randomInt(2, 2)
      }).toThrowErrorMatchingInlineSnapshot(`""max"(2) param should be greater than "min"(2)."`)
    })

    it('should throw if "min" is == "max" #3', () => {
      expect(() => {
        randomInt(0)
      }).toThrowErrorMatchingInlineSnapshot(`""max"(0) param should be greater than "min"(0)."`)
    })

    it('should throw if "min" is > "max" #1', () => {
      expect(() => {
        randomInt(2, 3)
      }).toThrowErrorMatchingInlineSnapshot(`""max"(2) param should be greater than "min"(3)."`)
    })

    it('should throw if "min" is > "max" #2', () => {
      expect(() => {
        randomInt(999, 2000)
      }).toThrowErrorMatchingInlineSnapshot(`""max"(999) param should be greater than "min"(2000)."`)
    })

    it('should throw if "min" is > "max" #3', () => {
      expect(() => {
        randomInt(0, 1)
      }).toThrowErrorMatchingInlineSnapshot(`""max"(0) param should be greater than "min"(1)."`)
    })

    it('should throw if "min" is > "max" #4', () => {
      expect(() => {
        randomInt(-5, 2)
      }).toThrowErrorMatchingInlineSnapshot(`""max"(-5) param should be greater than "min"(2)."`)
    })

    it('should throw if "min" is > "max" #5', () => {
      expect(() => {
        randomInt(-5, 0)
      }).toThrowErrorMatchingInlineSnapshot(`""max"(-5) param should be greater than "min"(0)."`)
    })

    it('should throw if "min" is > "max" #6', () => {
      expect(() => {
        randomInt(-5)
      }).toThrowErrorMatchingInlineSnapshot(`""max"(-5) param should be greater than "min"(0)."`)
    })

    it('should throw if "max" is `NaN`', () => {
      expect(() => {
        randomInt(NaN)
      }).toThrowErrorMatchingInlineSnapshot(`""max" param is not a number."`)
    })

    it('should throw if "min" is `NaN`', () => {
      expect(() => {
        randomInt(5, NaN)
      }).toThrowErrorMatchingInlineSnapshot(`""min" param is not a number."`)
    })

    describe('infinite arguments', () => {
      it('should throw if "max" is infinite [Infinity]', () => {
        expect(() => {
          randomInt(Infinity)
        }).toThrowErrorMatchingInlineSnapshot(`""max" param is not finite."`)
      })

      it('should throw if "max" is infinite [-Infinity]', () => {
        expect(() => {
          randomInt(-Infinity)
        }).toThrowErrorMatchingInlineSnapshot(`""max" param is not finite."`)
      })

      it('should throw if "max" is infinite [+Infinity]', () => {
        expect(() => {
          randomInt(+Infinity)
        }).toThrowErrorMatchingInlineSnapshot(`""max" param is not finite."`)
      })

      it('should throw if "min" is infinite [Infinity]', () => {
        expect(() => {
          randomInt(Infinity, Infinity)
        }).toThrowErrorMatchingInlineSnapshot(`""max" param is not finite."`)
      })

      it('should throw if "min" is infinite [-Infinity]', () => {
        expect(() => {
          randomInt(Infinity, -Infinity)
        }).toThrowErrorMatchingInlineSnapshot(`""max" param is not finite."`)
      })

      it('should throw if "min" is infinite [+Infinity]', () => {
        expect(() => {
          randomInt(Infinity, +Infinity)
        }).toThrowErrorMatchingInlineSnapshot(`""max" param is not finite."`)
      })
    })
  })
})
