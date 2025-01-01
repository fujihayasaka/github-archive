export const unsafeHTMLString = `
  <div>
    <h2>HTML Content with Safe and Unsafe Elements:</h2>

    <!-- Safe, regular HTML elements -->
    <p>This is a regular paragraph with <strong>bold</strong> and <em>italic</em> text.</p>
    <p>Here's a safe link: <a href="https://github.com">GitHub</a></p>

    <!-- Potentially dangerous elements -->
    <img src="x" alt="dangerous image" onerror="alert('XSS attempt via onerror')" />
    <a href="javascript:alert('XSS attempt via javascript: URL')">Malicious Link</a>
    <script>alert('XSS attempt via script tag')</script>
    <p onclick="alert('XSS attempt via onclick')">Click me (with onclick)</p>

    <!-- More safe content -->
    <p>Another safe paragraph with a <a href="/some/path">relative link</a></p>
    <p>And a paragraph with <a href="https://github.com" target="_blank">external link</a></p>

    <!-- More unsafe content -->
    <iframe src="https://evil.com"></iframe>
    <a href="data:text/html,<script>alert('data URL')</script>">Data URL Link</a>
  </div>
`

export const unsafeHTMLTextString = `This is an html string with <strong>strong</strong> and <em>emphasis</em>. It also has a <a href="https://github.com">link</a> and an unsafe script <script>alert('XSS')</script>.`
