import type {Pipeline} from '../types/app'

export function isDummyPipelineId(pipelineId: string) {
  return !!dummyPipelines.find(p => p.id === pipelineId)
}

export function isDummyPipeline(pipeline: Pipeline) {
  return !!(pipeline as unknown as {dummy: boolean}).dummy
}

export const dummyPipelines: Array<Pipeline & {dummy: true}> = [
  {
    id: 'dummy-1',
    dummy: true,
    title: 'Edit writing',
    description: 'Update writing to make it more engaging',
    updatedAt: '2025-01-01T00:00:00Z',
    nodes: [
      {
        id: '1a',
        title: 'Your writing',
        description: 'The writing you want to edit',
        type: 'text',
        inputType: {type: 'text'},
        content: `There is huge potential in building complex, repeatable pipelines that take advantage of LLM capabilities. A way for anyone to create and share tools. A few examples:

- Scientists sharing workflows for turning conference notes into a queryable artifact
- Scientists creating a pipeline for polishing a draft to adhere to proposal writing requirements
- Developers building a “check for security flaws” pipeline, accessible via API / vscode extension
- Library maintainers creating a “make a new codebase with Next.js" or “add Tailwind to your codebase” pipeline
- Artists building a pipeline to generate images of a certain style. Or process a sketch into a branded image.
- Generating a customized analysis of all of a lawyer’s cases
- Summarize medical research on a topic, using only the most trustable sources

I wager there’s a huge market in building and discovering pipelines, and a good implementation will look a bit like ChatGPT with people of many stripes building and using them.

GitHub is the right place for this kind of ecosystem for a few reasons:

- It ties into the spirit of Open Source
- It already has a huge audience to help with the cold start problem
- It mirror’s GitHub’s mission to make “code” accessible to a larger audience and the platform valuable to more than just developers. The future will look like people of any occupation “writing code” (really, just building things with logic)`,
      },
      {
        id: '2a',
        title: 'Edit guide',
        description: 'The guide on how to edit writing',
        type: 'text',
        inputType: {type: 'text'},
        content: `# Academish Voice

pvh / Aug 2022

Our publications follow what we call “*academish*” voice. We follow a largely academic style in our writing but avoid certain academic tendencies.

## Academic Style

- **Make no claims without support.** If you have made an unsupported claim consider its centrality to your argument. If “many developers agree”, we should be able to link to a source or describe how we know that. If you can’t defend it, you should get rid of it.
- **Avoid absolutist language.** It’s not “the main problem”, it’s “a problem”. (Unless, of course, you can defend the claim.)
- **Be precise and specific with your descriptions.** Instead of saying something “feels great”, describe how it feels. Don’t say something “is a problem” unless you describe what the problem is or to whom. If you’re tempted to say something vague because you’re not sure, either do enough research until you’re sure, or don’t say it.
- **Avoid hyperbole.** Use adjectives to add precision, not to persuade. Claiming “immense benefits” is only appropriate if you have developed a commercially viable fusion power plant. Delete words that are only for emphasis, and keep only those that add substance (e.g. quantify).
- **Structure your writing for incremental reading.** Don’t bury the lede. A reader should be able to understand the goals and conclusions of an essay by reading the first couple of paragraphs. Individual sections should briefly reiterate any important material and/or link back to where it is introduced. This may feel repetitive at times but aids readers who take several sessions to read a piece or who jump straight to the sections that interest them.
- **Give credit to others.** Cite earlier work. Link to sources for terms and ideas. Give thanks to contributors, reviewers, and advisors.
- **Be humble and transparent about shortcomings and problems.** We want readers to build on our work, not buy our product.

## Ink & Switch Style

- **Assume the reader is an interested generalist.** Explain jargon. Academic writing is dense with domain terminology because it assumes readers are “up to date on the field.”  Ink & Switch Essays make use of marginalia in what we call “asides” to define uncommon terminology. Concretely, you don’t need to gloss “HTML”, but you should probably gloss “CRDT”.
- **Carefully consider section headings.** Headings should legibly communicate the shape of the essay and serve as a roadmap for a reader to skip to the part of an essay that’s most interesting to them. Similarly, avoid including unrelated material in a section with a particular title. If a user already knows “How CRDTs Work” then they shouldn’t miss (much) important information about the project by skipping reading that section.
- **Embrace interactive demonstrations, animations, illustration, and videos.** Sometimes an illustration or demo can offer more clarity on a topic than text alone. As long as the content is self-contained and doesn’t rely on external sources, it should be legible for many years to come and viewable offline.
- **It’s okay to share hunches and beliefs as long as they’re appropriately labeled.** Don’t be shy about drawing conclusions, just be clear about the degree of confidence you have and where it comes from.
- **Ensure content looks good in PDF / printed form.** Obviously you lose the elements above, but the PDF version of a paper shouldn’t have giant ▶️ icons obscuring an image. Interactive figures should display a meaningful static view.
- **Use “asides” for supportive content and marginalia.** Asides can expand on references to other work, link out to related projects, or just share interesting context or historical tidbits.
- **Deploy persuasive or emotional writing appropriately.** You can be enthusiastic in describing your goals but be modest in how you describe your solutions.
- **Keep it classy.** We don’t dismiss other people’s work or insult their products. Everything around you was made by someone working really hard on it. If we have found a better way, we should show gratitude to those who helped us realize the path forward and humility about our contributions.
- **Sweat the details.** Make sure your colors are carefully chosen. Images should be clear and at the right bit rate. Choose your words carefully. Interactions should be delightful.

The result of these elements should be an essay that is confident, accurate, and readable to almost anyone with a background in technology. Our essays are often long (probably too long) but should consistently reward patient reading and serve as a reference to their readers for many years to come.

---

## About this page

This document aims to articulate the stylistic elements and voice of Ink & Switch Essays.

### **September 1, 2022**

@Martin Kleppmann added some details on academic style.

### **August 17, 2022**

@Todd Matthews made some formatting edits for continuity and scanability.

### **August 16, 2022**

@Peter van Hardenberg created this document. Began with @Adam Wiggins’ "Essay Playbook" and added notes about Academish Voice, which aim to capture the stylistic elements he looks for when I reading essay drafts. Many of these elements came from @Martin Kleppmann  and @Adam Wiggins reviews of my past writing, so credit to them. This is probably quite useful for everyone working on an essay right now, but is probably not comprehensive. If I've missed anything or anything here is controversial or unclear please feel free to inquire.`,
      },
      {
        id: '3a',
        title: 'Edited writing',
        description: 'Writing with suggested changes',
        type: 'prompt',
        content:
          "You're a helpful writing tutor here to suggest changes to the writing. Use this guide: {{2a}}. Respond with a full, edited version of {{1a}}. You're a helpful writing tutor here to suggest changes to the writing. Use this guide: {{2a}}. Respond with a full, edited version of {{1a}}. You're a helpful writing tutor here to suggest changes to the writing. Use this guide: {{2a}}. Respond with a full, edited version of {{1a}}.",
      },
    ],
  },
  {
    id: 'dummy-2',
    dummy: true,
    title: 'Document this function',
    description: "Document this function so it's easy to understand",
    updatedAt: '2025-01-01T00:00:00Z',
    nodes: [
      {
        id: '1b',
        title: 'Function to document',
        description: 'The function to document',
        content: `export function createNodePrompt(node: Node, nodeMap: Record<string, Node>): string {
  let content = node.content;
  const regex = /{{([\\w-]+)}}/g;
  let match;

  while ((match = regex.exec(content)) !== null) {
    const id = match[1];
    const referencedNode = nodeMap[id];
    if (referencedNode) {
      const replacementContent = createNodePrompt(referencedNode, nodeMap);
      content = content.replace(match[0], replacementContent);
    }
  }

  return content;
}`,
        type: 'code',
      },
      {
        id: '2b',
        title: 'Documentation guide',
        description: 'The documentation for the function',
        content: `Minimum Viable Documentation
A small set of fresh and accurate docs is better than a large assembly of “documentation” in various states of disrepair.

Write short and useful documents. Cut out everything unnecessary, including out-of-date, incorrect, or redundant information. Also make a habit of continually massaging and improving every doc to suit your changing needs. Docs work best when they are alive but frequently trimmed, like a bonsai tree.

See also these Agile Documentation best practices.

Update Docs with Code
Change your documentation in the same CL as the code change. This keeps your docs fresh, and is also a good place to explain to your reviewer what you’re doing.

A good reviewer can at least insist that docstrings, header files, README.md files, and any other docs get updated alongside the CL.

Delete Dead Documentation
Dead docs are bad. They misinform, they slow down, they incite despair in engineers and laziness in team leads. They set a precedent for leaving behind messes in a code base. If your home is clean, most guests will be clean without being asked.

Just like any big cleaning project, it’s easy to be overwhelmed. If your docs are in bad shape:

Take it slow, doc health is a gradual accumulation.
First delete what you’re certain is wrong, ignore what’s unclear.
Get your whole team involved. Devote time to quickly scan every doc and make a simple decision: Keep or delete?
Default to delete or leave behind if migrating. Stragglers can always be recovered.
Iterate.
Prefer the Good Over the Perfect
Documentation is an art. There is no perfect document, there are only proven methods and prudent guidelines. See Better is better than best.

Documentation is the Story of Your Code
Writing excellent code doesn’t end when your code compiles or even if your test coverage reaches 100%. It’s easy to write something a computer understands, it’s much harder to write something both a human and a computer understand. Your mission as a Code Health-conscious engineer is to write for humans first, computers second. Documentation is an important part of this skill.

There’s a spectrum of engineering documentation that ranges from terse comments to detailed prose:

Meaningful names: Good naming allows the code to convey information that would otherwise be relegated to comments or documentation. This includes nameable entities at all levels, from local variables to classes, files, and directories.

Inline comments: The primary purpose of inline comments is to provide information that the code itself cannot contain, such as why the code is there.

Method and class comments:

Method API documentation: The header / Javadoc / docstring comments that say what methods do and how to use them. This documentation is the contract of how your code must behave. The intended audience is future programmers who will use and modify your code.

It is often reasonable to say that any behavior documented here should have a test verifying it. This documentation details what arguments the method takes, what it returns, any “gotchas” or restrictions, and what exceptions it can throw or errors it can return. It does not usually explain why code behaves a particular way unless that’s relevant to a developer’s understanding of how to use the method. “Why” explanations are for inline comments. Think in practical terms when writing method documentation: “This is a hammer. You use it to pound nails.”

Class / Module API documentation: The header / Javadoc / docstring comments for a class or a whole file. This documentation gives a brief overview of what the class / file does and often gives a few short examples of how you might use the class / file.

Examples are particularly relevant when there’s several distinct ways to use the class (some advanced, some simple). Always list the simplest use case first.

README.md: A good README.md orients the new user to the directory and points to more detailed explanation and user guides:

What is this directory intended to hold?
Which files should the developer look at first? Are some files an API?
Who maintains this directory and where I can learn more?
See the README.md guidelines.

docs: The contents of a good docs directory explain how to:

Get started using the relevant API, library, or tool.
Run its tests.
Debug its output.
Release the binary.
Design docs, PRDs: A good design doc or PRD discusses the proposed implementation at length for the purpose of collecting feedback on that design. However, once the code is implemented, design docs should serve as archives of these decisions, not as half-correct docs (they are often misused).

Other external docs: Some teams maintain documentation in other locations, separate from the code, such as Google Sites, Drive, or wiki. If you do maintain documentation in other locations, you should clearly point to those locations from your project directory (for example, by adding an obvious link to the location from your project’s README.md).

Duplication is Evil
Do not write your own guide to a common Google technology or process. Link to it instead. If the guide doesn’t exist or it’s badly out of date, submit your updates to the appropriate directory or create a package-level README.md. Take ownership and don’t be shy: Other teams will usually welcome your contributions.`,
        type: 'text',
        inputType: {type: 'text'},
      },
      {
        id: '3b',
        title: 'My personal skillset',
        description: '',
        content: `I'm a software engineer with 5 years of experience in building web applications. I'm skilled in JavaScript, TypeScript, React, and Node.js. I'm also familiar with Python and have experience with machine learning frameworks like TensorFlow and PyTorch. I'm comfortable with SQL and NoSQL databases, and have experience with Docker and Kubernetes. I'm a quick learner and I'm always looking to improve my skills.`,
        type: 'text',
        inputType: {type: 'text'},
      },
      {
        id: '4b',
        title: 'Documented code',
        description: 'The code with documentation',
        content: `You're documenting your code for your team.\n\nUpdate this code: {{1b}}\n\nUsing this guide: {{2b}}]\n\nAnd incorporate {{3b}}`,
        type: 'prompt',
      },
      {
        id: '5b',
        title: 'Function tests',
        description: 'Generate a test for the code',
        content: `You're generating a Jest test for {{4b}}. Our testing guidelines: {{6b}}`,
        type: 'prompt',
      },
      {
        id: '6b',
        title: 'Testing guidelines',
        description: 'The guidelines for testing',
        content: `The Test Anatomy

⚪ ️ 1.1 Include 3 parts in each test name
✅ Do: A test report should tell whether the current application revision satisfies the requirements for the people who are not necessarily familiar with the code: the tester, the DevOps engineer who is deploying and the future you two years from now. This can be achieved best if the tests speak at the requirements level and include 3 parts:

(1) What is being tested? For example, the ProductsService.addNewProduct method

(2) Under what circumstances and scenario? For example, no price is passed to the method

(3) What is the expected result? For example, the new product is not approved


❌ Otherwise: A deployment just failed, a test named “Add product” failed. Does this tell you what exactly is malfunctioning?


👇 Note: Each bullet has code examples and sometime also an image illustration. Click to expand



⚪ ️ 1.2 Structure tests by the AAA pattern
✅ Do: Structure your tests with 3 well-separated sections Arrange, Act & Assert (AAA). Following this structure guarantees that the reader spends no brain-CPU on understanding the test plan:

1st A - Arrange: All the setup code to bring the system to the scenario the test aims to simulate. This might include instantiating the unit under test constructor, adding DB records, mocking/stubbing on objects, and any other preparation code

2nd A - Act: Execute the unit under test. Usually 1 line of code

3rd A - Assert: Ensure that the received value satisfies the expectation. Usually 1 line of code


❌ Otherwise: Not only do you spend hours understanding the main code but what should have been the simplest part of the day (testing) stretches your brain


⚪ ️1.3 Describe expectations in a product language: use BDD-style assertions
✅ Do: Coding your tests in a declarative-style allows the reader to get the grab instantly without spending even a single brain-CPU cycle. When you write imperative code that is packed with conditional logic, the reader is forced to exert more brain-CPU cycles. In that case, code the expectation in a human-like language, declarative BDD style using expect or should and not using custom code. If Chai & Jest doesn't include the desired assertion and it’s highly repeatable, consider extending Jest matcher (Jest) or writing a custom Chai plugin

❌ Otherwise: The team will write less tests and decorate the annoying ones with .skip()


⚪  1.4 Stick to black-box testing: Test only public methods
✅ Do: Testing the internals brings huge overhead for almost nothing. If your code/API delivers the right results, should you really invest your next 3 hours in testing HOW it worked internally and then maintain these fragile tests? Whenever a public behavior is checked, the private implementation is also implicitly tested and your tests will break only if there is a certain problem (e.g. wrong output). This approach is also referred to as behavioral testing. On the other side, should you test the internals (white box approach) — your focus shifts from planning the component outcome to nitty-gritty details and your test might break because of minor code refactors although the results are fine - this dramatically increases the maintenance burden

❌ Otherwise: Your tests behave like the boy who cried wolf: shouting false-positive cries (e.g., A test fails because a private variable name was changed). Unsurprisingly, people will soon start to ignore the CI notifications until someday, a real bug gets ignored…


⚪  1.5 Choose the right test doubles: Avoid mocks in favor of stubs and spies
✅ Do: Test doubles are a necessary evil because they are coupled to the application internals, yet some provide immense value (Read here a reminder about test doubles: mocks vs stubs vs spies).

Before using test doubles, ask a very simple question: Do I use it to test functionality that appears, or could appear, in the requirements document? If not, it’s a white-box testing smell.

For example, if you want to test that your app behaves reasonably when the payment service is down, you might stub the payment service and trigger some ‘No Response’ return to ensure that the unit under test returns the right value. This checks our application behavior/response/outcome under certain scenarios. You might also use a spy to assert that an email was sent when that service is down — this is again a behavioral check which is likely to appear in a requirements doc (“Send an email if payment couldn’t be saved”). On the flip side, if you mock the Payment service and ensure that it was called with the right JavaScript types — then your test is focused on internal things that have nothing to do with the application functionality and are likely to change frequently

❌ Otherwise: Any refactoring of code mandates searching for all the mocks in the code and updating accordingly. Tests become a burden rather than a helpful friend



⚪ 1.6 Don’t “foo”, use realistic input data
✅ Do: Often production bugs are revealed under some very specific and surprising input — the more realistic the test input is, the greater the chances are to catch bugs early. Use dedicated libraries like Chance or Faker to generate pseudo-real data that resembles the variety and form of production data. For example, such libraries can generate realistic phone numbers, usernames, credit cards, company names, and even ‘lorem ipsum’ text. You may also create some tests (on top of unit tests, not as a replacement) that randomize fakers' data to stretch your unit under test or even import real data from your production environment. Want to take it to the next level? See the next bullet (property-based testing).

❌ Otherwise: All your development testing will falsely show green when you use synthetic inputs like “Foo”, but then production might turn red when a hacker passes-in a nasty string like “@3e2ddsf . ##’ 1 fdsfds . fds432 AAAA”

`,
        type: 'text',
        inputType: {type: 'text'},
      },
      {
        id: '7b',
        title: 'Test results',
        description: 'Run the test for the code',
        content: `You're running tests for {{5b}}. Respond with the results of the tests.`,
        type: 'prompt',
      },
      {
        id: '8',
        title: 'Documented and tested code',
        description: 'The code with documentation and test',
        content: `Here's the documented code: {{4b}}.\n\nHere's the {{5b}} and the {{7b}}.\n\nRespond with "✅ OK" if the tests all pass, and show a code block with the documented code and tests.`,
        type: 'prompt',
      },
    ],
  },
  {
    id: 'dummy-3',
    dummy: true,
    title: 'Generate a course teaching me how this code works',
    description: 'Generate a course teaching me how this code works',
    updatedAt: '2025-01-01T00:00:00Z',
    nodes: [
      {
        id: '1c',
        title: 'Code to explain',
        description: 'The code to explain',
        content: `import {ticks, tickIncrement} from "d3-array";
import continuous, {copy} from "./continuous.js";
import {initRange} from "./init.js";
import tickFormat from "./tickFormat.js";

export function linearish(scale) {
  var domain = scale.domain;

  scale.ticks = function(count) {
    var d = domain();
    return ticks(d[0], d[d.length - 1], count == null ? 10 : count);
  };

  scale.tickFormat = function(count, specifier) {
    var d = domain();
    return tickFormat(d[0], d[d.length - 1], count == null ? 10 : count, specifier);
  };

  scale.nice = function(count) {
    if (count == null) count = 10;

    var d = domain();
    var i0 = 0;
    var i1 = d.length - 1;
    var start = d[i0];
    var stop = d[i1];
    var prestep;
    var step;
    var maxIter = 10;

    if (stop < start) {
      step = start, start = stop, stop = step;
      step = i0, i0 = i1, i1 = step;
    }

    while (maxIter-- > 0) {
      step = tickIncrement(start, stop, count);
      if (step === prestep) {
        d[i0] = start
        d[i1] = stop
        return domain(d);
      } else if (step > 0) {
        start = Math.floor(start / step) * step;
        stop = Math.ceil(stop / step) * step;
      } else if (step < 0) {
        start = Math.ceil(start * step) / step;
        stop = Math.floor(stop * step) / step;
      } else {
        break;
      }
      prestep = step;
    }

    return scale;
  };

  return scale;
}

export default function linear() {
  var scale = continuous();

  scale.copy = function() {
    return copy(scale, linear());
  };

  initRange.apply(scale, arguments);

  return linearish(scale);
}`,
        type: 'code',
      },
      {
        id: '2c',
        title: 'My skillset',
        description: 'My skillset',
        content: `I'm a software engineer with 5 years of experience in building web applications. I'm skilled in JavaScript, TypeScript, React, and Node.js. I'm also familiar with Python and have experience with machine learning frameworks like TensorFlow and PyTorch. I'm comfortable with SQL and NoSQL databases, and have experience with Docker and Kubernetes. I'm a quick learner and I'm always looking to improve my skills.`,
        type: 'text',
        inputType: {type: 'text'},
      },
      {
        id: '3c',
        title: 'Course outline',
        description: 'The outline of the course',
        content: `You're generating a course teaching me how to understand {{1c}}. I have the following skillset: {{2c}}. Keep it short and concise, with 2-3 sections.`,
        type: 'prompt',
      },
      {
        id: '4c',
        title: 'Course content',
        description: 'The content of the course',
        content: `Generate a short walkthrough that teaches me how to understand {{1c}}. I have the following skillset: {{2c}}.\n\nFlesh out the {{3c}}. Respond with a short walkthrough, using code blocks for code samples.`,
        type: 'prompt',
      },
    ],
  },
  {
    id: 'dummy-4',
    dummy: true,
    title: 'Generate app name',
    description: 'Generate and validate potential names for your app',
    updatedAt: '2025-01-01T00:00:00Z',
    nodes: [
      {
        id: '1d',
        title: 'App description',
        description: "Describe your app's purpose and target audience",
        type: 'text',
        inputType: {type: 'text'},
        content: 'An email app that uses AI to help you write emails faster.',
      },
      {
        id: '2d',
        title: 'Generate names',
        description: 'Generate potential names based on description',
        type: 'prompt',
        content: `You're a creative app naming expert. Generate 10 potential names for an app based on this description: {{1d}}

Rules for the names:
- Keep them short and memorable
- Make sure they're easy to spell
- Consider domain name availability
- Avoid trademarked terms

Format: a JSON array with one name per line`,
      },
      {
        id: '3d',
        title: 'Check domain availability',
        description: 'Check if domains are available for the generated names',
        type: 'code',
        content: `// This code checks domain availability using DNS lookup
  const nameList = {{2d}}

  const results = [];

  for (const name of nameList) {
    const cleanName = name.toLowerCase().replace(/[^a-z0-9]/g, '');
    const domain = cleanName + '.com';

    try {
      // Try to resolve the domain - if it fails, domain might be available
      const response = await fetch(\`https://dns.google/resolve?name=\${domain}\`);
      const data = await response.json();

      results.push({
        name: name,
        domain: domain,
        available: data.Status === 3 || !data.Answer // NXDOMAIN status or no answer means likely available
      });
    } catch (error) {
      results.push({
        name: name,
        domain: domain,
        error: 'Failed to check availability'
      });
    }
  }

  return results;
`,
      },
    ],
  },
  {
    id: 'dummy-5',
    dummy: true,
    title: 'Wikipedia',
    description: 'Generate a wiki article on a topic or question',
    updatedAt: '2025-01-01T00:00:00Z',
    nodes: [
      {
        id: '1e',
        title: 'Topic or question',
        description: 'The topic or question to generate a wiki article on',
        type: 'text',
        inputType: {type: 'text'},
        content: 'When do babies start to crawl?',
      },
      {
        id: '2e',
        title: 'Split into topics',
        description: 'Split the topic or question into topics',
        type: 'text',
        inputType: {type: 'text'},
        content: `You're creating a write-up on a concept. You need to split it into 5-6 sections that cover interesting aspects of the concept. Respond with a JSON array with one string per topic.

For example:
Concept: Dogs as pets
Topics:
["Dog breeds", "Dog training", "Dog costs", "Dog health", "Dog accessories"]


Concept: {{1e}}
Topics:`,
      },
      {
        id: '3e',
        title: 'Generate article',
        description: 'Generate a wiki article on the concept',
        type: 'prompt',
        content: `You're a wiki article generator. Generate a wiki article on the concept: {{1e}}. Split it into sections: {{2e}} with a title, a bolded key statement, and a list or 2 paragraphs.`,
      },
      {
        id: '4e',
        title: 'Image',
        description: 'An image for the article',
        type: 'prompt',
        content: `Generate an ascii art image for the article: {{3e}}`,
      },
    ],
  },
  {
    id: 'dummy-6',
    dummy: true,
    title: 'Compare two prompts',
    description: 'Compare the performance of two prompts',
    updatedAt: '2025-01-01T00:00:00Z',
    nodes: [
      {
        id: '1f',
        title: 'Prompt 1',
        description: 'The first prompt to compare',
        type: 'prompt',
        content: 'Make me a haiku about the color blue',
      },
      {
        id: '2f',
        title: 'Prompt 2',
        description: 'The second prompt to compare',
        type: 'prompt',
        content: 'You are a haiku generator. Make a haiku about the color blue. Your job depends on it.',
      },
      {
        id: '3f',
        title: 'Important metrics',
        description: 'The important metrics to compare the prompts on',
        type: 'text',
        inputType: {type: 'text'},
        content: 'Relevance, creativity, accuracy, completeness, and style',
      },
      {
        id: '4f',
        title: 'Compare',
        description: 'Compare the performance of the two prompts',
        type: 'prompt',
        content: `For each of the {{3f}}, compare the two prompts: {{1f}} and {{2f}}. Respond with a JSON array with one object per metric, with the metric name and a winner key that says which prompt is better (just say 1 or 2).`,
      },
    ],
  },
]
