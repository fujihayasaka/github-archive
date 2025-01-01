import {CLIENT_SKILL_REGISTRY} from '../../client-skills-registry'

describe('CLIENT_SKILL_REGISTRY', () => {
  for (const skill of Object.values(CLIENT_SKILL_REGISTRY)) {
    it('should have a valid schema', () => {
      expect(skill.schema).not.toBeNull()
    })

    it('should have valid required parameters', () => {
      const schema = skill.schema
      const required = schema.function.parameters?.required ?? []
      for (const requiredParam of required) {
        // requiredParam should not contain special characters. It's easy to make a typo here a la ['item 1, item2'] so this is an extra safeguard.
        expect(requiredParam).not.toMatch(/[^\w-]/)
      }
    })
  }
})
