-- Enable RLS on the insights table
ALTER TABLE insights ENABLE ROW LEVEL SECURITY;

-- Policy: Allow users to SELECT insights in their own workspace
CREATE POLICY "Select insights in workspace"
ON insights
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND users.workspace_id = insights.workspace_id
  )
);

-- Policy: Allow users to INSERT insights in their own workspace
CREATE POLICY "Insert insights in workspace"
ON insights
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND users.workspace_id = insights.workspace_id
  )
);

-- Policy: Allow users to UPDATE their own insights
CREATE POLICY "Update own insights"
ON insights
FOR UPDATE
USING (
  insights.created_by = auth.uid()
);

-- Policy: Allow users to DELETE their own insights
CREATE POLICY "Delete own insights"
ON insights
FOR DELETE
USING (
  insights.created_by = auth.uid()
);
