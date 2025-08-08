-- Enable RLS on the vector_store table
ALTER TABLE vector_store ENABLE ROW LEVEL SECURITY;

-- Policy: Allow SELECT if user can access the parent insight
CREATE POLICY "Select vectors if user can access parent insight"
ON vector_store
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM insights
    WHERE insights.id = vector_store.insight_id
    AND EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.workspace_id = insights.workspace_id
    )
  )
);

-- Policy: Allow INSERT if user can access the parent insight
CREATE POLICY "Insert vectors if user can access parent insight"
ON vector_store
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM insights
    WHERE insights.id = vector_store.insight_id
    AND EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.workspace_id = insights.workspace_id
    )
  )
);
