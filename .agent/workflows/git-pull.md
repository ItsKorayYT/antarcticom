---
description: How to handle git pull conflicts safely
---

If you see an error like "your local changes would be overwritten" or "untracked files would be overwritten":

1. Backup your local changes temporarily:
   ```powershell
   git stash push -u -m "pre-pull-backup"
   ```

2. Get the latest code from the server:
   ```powershell
   git pull
   ```

3. Re-apply your local changes:
   ```powershell
   git stash pop
   ```

4. If you see "CONFLICT" messages:
   - Open the affected files in VS Code.
   - Use the "Accept Incoming", "Accept Current", or "Compare" buttons at the top of the conflict block.
   - Save the file once resolved.

5. Finalize the merge:
   ```powershell
   git add .
   git commit -m "Merge and resolve conflicts"
   ```
