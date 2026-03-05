# /enzyme:digest

Generate an `.enzyme` digest for a folder.

## Usage

```
/enzyme:digest <path>
/enzyme:digest ./src
/enzyme:digest ./cloudy-ideas --inline 80
```

## Behavior

1. Run the enzyme CLI on the specified path
2. Generate a `.enzyme` file in that folder
3. Report compression stats

## Implementation

Execute: `bash <plugin-dir>/bin/enzyme.sh <path>`

If no path is specified, prompt the user for one.
