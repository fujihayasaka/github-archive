# *`go-crpc` has been renamed `go-chatops`*!!!

- Versions go-crpc v2.0.0 through v2.13.1 have been ported directly to go-chatops.
- Version go-crpc v2.13.2 exists solely to add deprecation notices.

### Easy steps to switch from go-crpc to go-chatops

0. Check and see if you have any modules, variables, functions, or methods named exactly `chatops` in your repo already. If you do...then you'll have to be more careful about your approach.
1. Replace all instances of `crpc` with `chatops` in your entire repository (cmd-shift-H to replace-in-files in VS Code--turn on case sensitivity!).
2. Carefully inspect the diff and make sure you didn't replace something unrelated.† Revert any problem changes.
3. `rm go.sum`
4. `go mod tidy`

All future development work will be done in the [go-chatops](https://github.com/github/go-chatops) repository.


†You'd think `crpc` would be easy enough to search-and-replace without mishaps, but it happens. Can you spot the search/replace mistake below? 😆

```diff
-  integrity sha512-C/CPBqKWnvdcxqIARxyOh4v1UUEOCHpgDa0WYgpKDFMszcrPcffg5uhwSgPCLD2WWxmq6isisz87tzT01tuGhg==
+  integrity sha512-C/CPBqKWnvdcxqIARxyOh4v1UUEOCHpgDa0WYgpKDFMszchatopsffg5uhwSgPCLD2WWxmq6isisz87tzT01tuGhg==
```
