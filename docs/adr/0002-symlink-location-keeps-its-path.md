# Symlink location keeps its path

Entering a **symlink** to a directory leaves the panel at that symlink's path. Any **location** reached through it stays on that path, including when the path repeats, and going up walks back one step. The directory the symlink points at is not the location. Resolving the panel onto the target was rejected: going up would leave the folder that contains the link.

Status: accepted
