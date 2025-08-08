-- Enable RLS on the voice_sessions table
ALTER TABLE voice_sessions ENABLE ROW LEVEL SECURITY;

-- Policy: Allow SELECT if user is the owner
CREATE POLICY "Select own voice sessions"
ON voice_sessions
FOR SELECT
USING (
  voice_sessions.created_by = auth.uid()
);

-- Policy: Allow INSERT only for self
CREATE POLICY "Insert own voice session"
ON voice_sessions
FOR INSERT
WITH CHECK (
  voice_sessions.created_by = auth.uid()
);

-- Policy: Allow UPDATE if user is the owner
CREATE POLICY "Update own voice sessions"
ON voice_sessions
FOR UPDATE
USING (
  voice_sessions.created_by = auth.uid()
);

-- Policy: Allow DELETE if user is the owner
CREATE POLICY "Delete own voice sessions"
ON voice_sessions
FOR DELETE
USING (
  voice_sessions.created_by = auth.uid()
);
