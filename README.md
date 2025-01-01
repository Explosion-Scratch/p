# p (Pop) - A Smarter `cd` Command

`p` is a smarter `cd` command. It searches recursively and uses fzf when needed. See below for details.

## Features

- **Fuzzy Matching**: Navigate to directories using partial or approximate names.
- **Ignore Rules**: Automatically ignores common directories like `node_modules`, `.git`, and more.
- **Depth Control**: Limit the search depth to avoid traversing too deep into the directory tree.
- **Shell Integration**: Seamlessly integrate with popular shells like `bash`, `zsh`, and `fish`.
- **Interactive Selection**: Use `fzf` for interactive directory selection when multiple matches are found.
- **Verbose Logging**: Enable detailed logging for debugging and understanding the matching process.

## Installation

1. **Install `bun`**: Ensure you have `bun` installed on your system. Follow the instructions on the [Bun website](https://bun.sh/).

2. **Download `p`**: Download the file `p` and save it somewhere in `$PATH`.

3. **Install `fzf`**: `p` uses `fzf` for interactive selection. Install it using your package manager:

    ```sh
    # On macOS
    brew install fzf

    # On Ubuntu
    sudo apt-get install fzf

    # On Arch Linux
    sudo pacman -S fzf
    ```

## Usage

```sh
p [options] <directory-pattern>
```

### Options

- `-h, --help`: Show the help message.
- `--completion [shell]`: Generate shell completion script (bash, zsh, fish).
- `--init [shell]`: Generate shell initialization script (bash, zsh, fish).
- `-t, --threshold <number>`: Set minimum score threshold (default: 0).
- `-v, --verbose`: Enable verbose logging.
- `--more`: Show all matches without filtering.
- `--first`: Always go to the first match.

### Examples

- `p proj`: Fuzzy search for directories matching 'proj'.
- `p web/src`: Search for 'web' then 'src' within matches.
- `p --threshold 5`: Only show matches with score >= 5.
- `p --more`: Show all matches without filtering.
- `p --first`: Always go to the first match.

## Shell Integration

To enable directory changing, you must add shell integration to your RC file. Run `p --init [shell]` to generate the necessary script and add it to your shell configuration file. Otherwise p just logs the output.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.
