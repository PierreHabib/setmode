-- Enable RLS on the insight_versions table
ALTER TABLE insight_versions ENABLE ROW LEVEL SECURITY;

-- Policy: Allow users to SELECT versions if they can access the parent insight
CREATE POLICY "Select versions if user can access parent insight"
ON insight_versions
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM insights
    WHERE insights.id = insight_versions.insight_id
    AND EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.workspace_id = insights.workspace_id
    )
  )
);

-- Policy: Allow INSERT if user can access parent insight
CREATE POLICY "Insert versions if user can access parent insight"
ON insight_versions
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM insights
    WHERE insights.id = insight_versions.insight_id
    AND EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.workspace_id = insights.workspace_id
    )
  )
);
