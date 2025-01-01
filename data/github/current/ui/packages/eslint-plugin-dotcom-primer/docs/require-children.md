# Rule: `require-children`

The `require-children` ESLint rule warns when a specified React component (`parent`) is missing a specified child component (`child`).

The default warning message is:

> `<${parent}>` requires a `<${child}>` child, but one wasn’t provided. Check `<${parent}>`’s children.

## Configuration

### Example

```JSON
"rules": {
  "@github-ui/dotcom-primer/require-children": [
    "error",
    {
      "parent": "ChartCard",
      "child": "ChartCard.Title",
      "message": "Including <ChartCard.Title> improves chart accessibility.",
      "module": "@github-ui/chart-card",
    },
    {
      "parent": "ChartCard",
      "child": "ChartCard.Chart",
      "module": "@github-ui/chart-card",
    }
  ]
}
```

> [!NOTE]
> It’s possible to require _more than one_ child component per parent. The configuration above requires `ChartCard` to have a `ChartCard.Title` child _and_ a `ChartCard.Chart` child.

### Parameters

#### `parent`

**Required** The name of the parent React component. For example, `"ChartCard"`.

#### `child`

**Required** The name of the required child React component. For example, `"ChartCard.Title"`.

#### `message`

**Optional** Text to _append to_ the default warning message. For example, `"Including <ChartCard.Title> improves chart accessibility."`.

#### `module`

**Optional** The module from which `parent` is imported. For example, `"@github-ui/chart-card"`.

By default, components named `parent` from _any_ module are required to have the specified `child`; however, when two packages provide (different) components both named `parent` (coincidentally), this default behavior is undesirable. When `module` is specified, only `parent` components imported from the specified module will be checked.

## Examples

The following code examples assume the [configuration example](#configuration) above.

### **Incorrect** code for this rule 👎

```JSX
import {ChartCard} from "@github-ui/chart-card";

export function App() {
  return (
    <ChartCard>
      <ChartCard.Chart series={series} xAxisTitle={xAxisTitle} yAxisTitle={yAxisTitle} type={type} />
    </ChartCard>
  );
}

// Error:
// <ChartCard> requires a <ChartCard.Title> child, but one wasn’t provided. Check <ChartCard>’s children. Including <ChartCard.Title> improves chart accessibility. eslint(@github-ui/dotcom-primer/require-children)
```

```JSX
import {ChartCard} from "@github-ui/chart-card";

export function App() {
  return (
    <ChartCard>
      <ChartCard.Title>Accessible Chart</ChartCard.Title>
    </ChartCard>
  );
}

// Error:
// <ChartCard> requires a <ChartCard.Chart> child, but one wasn’t provided. Check <ChartCard>’s children. eslint(@github-ui/dotcom-primer/require-children)
```

### **Correct** code for this rule 👍

```JSX
import {ChartCard} from "@github-ui/chart-card";

export function App() {
  return (
    <ChartCard>
      <ChartCard.Title>Accessible Chart</ChartCard.Title>
      <ChartCard.Chart series={series} xAxisTitle={xAxisTitle} yAxisTitle={yAxisTitle} type={type} />
    </ChartCard>
  );
}

// No error: Required child components are present.
```

```JSX
import {ChartCard} from "./custom-chart-card";

export function App() {
  return (
    <ChartCard />
  );
}

// No error: A different ChartCard is used.
```

## Known issues

The rule is optimized to handle situations like this:

```JSX
<Parent>
  <Child></Child>
</Parent>
```

The more complexity involved with rendering `<Child>`, the less likely `require-children` is to find it. For example the rule may warn (incorrectly) when a child is conditionally rendered, spread, rendered via a wrapper, very deeply nested, etc.

For details about cases the rule can (and can’t) handle, review [this rule’s tests](../__tests__/require-children.test.tsx).
