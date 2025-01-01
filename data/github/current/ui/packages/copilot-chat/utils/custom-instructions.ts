export const suggestedPersonalInstructions: Record<string, Record<string, string>> = {
  Role: {
    tooltip: 'Role, domain, style, and focus areas',
    body: `Your role:\n- {role_type} expert in {domain}\n- Focus on {key_skill_area}\n`,
  },
  Communication: {
    tooltip: 'Language, tone and format',
    body: `Communication:\n- Write in {tone/language}\n- Reference {source_type} documentation\n- Structure responses as {format}\n`,
  },
  'Code preferences': {
    tooltip: 'Code style, patterns, and conventions',
    body: `Code guidelines:\n- Use {language} conventions\n- Follow {pattern/code_guidelines}\n- Optimize for {goal}\n`,
  },
}
