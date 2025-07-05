# Sparrow.vim (WIP)
File synchronization tool under nvim.

# Features:
- Project-level synchronization configuration file, different projects can be configured with different rules.
- Fuzzy selection of target host, support for one project corresponding to multiple host synchronization requirements; also supports fixed target host.
- One project supports the configuration of multiple synchronization rules, including file rules, directory rules, automatic rule generation, etc.
- Backup/restore of synchronization target location files.
- Compare the differences between local and target location files, support syntax highlighting.
- Target host check to avoid incorrect synchronization.
- Support multiple transmission tools, including SCP, RSync, FTP, etc.
- Support file synchronization based on version control tools, such as branch difference synchronization, etc.
- Multi-directional synchronization, such as upload and download.
- Definition of pre- and post-synchronization commands at the synchronization rule level
