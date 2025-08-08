-- Enable RLS on the insight_relations table
ALTER TABLE insight_relations ENABLE ROW LEVEL SECURITY;

-- Policy: Allow SELECT if user can access both source and target insights
CREATE POLICY "Select if user can access both related insights"
ON insight_relations
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM insights
    WHERE insights.id = insight_relations.source_insight_id
    AND EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.workspace_id = insights.workspace_id
    )
  )
  AND
  EXISTS (
    SELECT 1 FROM insights
    WHERE insights.id = insight_relations.target_insight_id
    AND EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.workspace_id = insights.workspace_id
    )
  )
);

-- Policy: Allow INSERT if user can access both insights
CREATE POLICY "Insert if user can access both related insights"
ON insight_relations
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM insights
    WHERE insights.id = insight_relations.source_insight_id
    AND EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.workspace_id = insights.workspace_id
    )
  )
  AND
  EXISTS (
    SELECT 1 FROM insights
    WHERE insights.id = insight_relations.target_insight_id
    AND EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.workspace_id = insights.workspace_id
    )
  )
);
