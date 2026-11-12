# Input Content Filtering

Padawan currently generates a problem statement from issue and PR titles, bodies, and comments. This content is then passed to the LLM for processing. However, this content may contain HTML or markdown that is not visible to users, but could be visible to the LLM. This could lead to unintended consequences, such as the LLM being acting on hidden directives. The following document describes how to filter this content to reduce risk.

It is an adaptation of the [Copilot rendering specification](https://github.com/github/copilot/blob/main/docs/client-guidance/rendering-guidelines.md) that defines how user facing content should be rendered.

This document will focus on filtering LLM **input** originating from GitHub PRs and issues, `copilot-instructions.md`, or other classes of AI-facing user input. Since we can assume the content is in a GitHub-flavored markdown form here, we can adapt the rules for this specific scenario. (Note that we also use CAPI for LLM calls, so any rules that are applied to CAPI may applied as well.)

However, note that these rules are not directly applied to non-AI-instruction repository files Padawan modifies because this breaks its ability to diff and change them. Files like `copilot-instructions.md` are directly intended for LLM consumption and therefore are a special case since they are a form of "UI" for the LLM.

### Invisible tag and bi-directional unicode modifiers should be removed

In general, hidden Unicode characters should be removed. See [this article](https://www.pillar.security/blog/new-vulnerability-in-github-copilot-and-cursor-how-hackers-can-weaponize-code-agents) for information on why these pose a risk to LLM input. In particular:

1. The Unicode "tags" range must be removed: `U+E0001`, `U+E0020-U+E007F` ([Doc](https://www.unicode.org/charts/PDF/UE0000.pdf))
1. BiDI / Bi-directional control characters should also be removed: `U+202A-U+202E`, `U+2066-U+2069` ([Related issue](https://github.com/github/pull-requests/issues/16881))
1. The following hidden modifier characters are also removed: `U+200B`, `U+200C`, `U+200E`, `U+200F`, `U+00AD`, `U+FEFF`, `U+180E`, `U+2060-U+2064`. These are all highlighed by the [ASCII smuggler tool](https://embracethered.com/blog/ascii-smuggler.html). However, `U+200D` is a [zero width joiner that can modify Emojis](https://www.unicode.org/reports/tr51/), so it has an affect on UX and requests to replace them - which has been a surprisingly common occurrence given their presence in READMEs and CLIs. It does not directly impact the LLM's behavior, so it is not currently removed.

[Easily confused characters](https://www.unicode.org/Public/security/revision-03/confusablesSummary.txt) are visible and therefore **not** currently filtered.

### Markdown code blocks

In markdown, all characters within code blocks are visible to users, and thus can be visible to AI. Invisible characters still need to be filtered, but HTML can be left alone.

### HTML outside of markdown code blocks

#### Strip HTML attributes

Whether embedded in markdown or as straight HTML, HTML attributes can be easily hidden from users. After filtering, the only attributes that should remain are:

- `img`: src
- `a`: href

Any `img` `src` or `a` `href` attribute that cannot be parsed as a URL should be removed, and can only reference `http(s)` URLs.

#### HTML tags

If markdown is transformed to HTML, that should happen before filtering to simplify logic, though technically this conversation is optional.

Regardless, after processing only the follow HTML tags should remain after filtering:

- b
- blockquote
- br
- code
- em
- h1
- h2
- h3
- h4
- h5
- h6
- hr
- i
- li
- ol
- p
- pre
- strong
- sub
- sup
- table
- tbody
- td
- th
- thead
- tr
- ul

All other tags should be **removed**. Only the attributes mentioned above should remain.

#### Custom XML tags
The following XML elements are allowed in problem statement to steer the LLM, and should be preserved if present. This is safe since content within these tags is visible to users on GitHub.

- comments
- issue_title
- issue_description
- pr_title
- pr_description
- pr_reviews
- pr_comments
- comment_thread
- comment_id
- comment_old
- comment_new
- thread_id
- commit
- original_commit
- file
- author
- agent_instructions

Here again, **no attributes** should be preserved.

### Parsing referenced images

Copilot coding agent now supports parsing referenced images. However, given these are visible, they are consumed and processed by the LLM. However:
- Nothing other than the `src` attribute for the `img` tag should be preserved.
- Only `http` and `https` URLs should be allowed.

We also need to do similar processing to markdown image references, which have the form `![alt text](url "title")`:
- Remove title
- Replace the alt text with a generic `![image]` alt text.
- The URL should be preserved if it is an `http` or `https` URL.

### Markdown links
Like images, markdown links have the form `[link text](url "title")`. The link text is visible to users, so it should be preserved. However, the title is not visible, so it should be removed. The URL should be preserved if it is an `http` or `https` URL.