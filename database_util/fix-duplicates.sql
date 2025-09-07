-- Fix duplicate entries in tag table
-- First, let's see what duplicates we have
SELECT id, COUNT(*) as count_duplicates 
FROM tag 
GROUP BY id 
HAVING COUNT(*) > 1;

-- Remove duplicates, keeping only the first occurrence
DELETE FROM tag 
WHERE ctid NOT IN (
    SELECT MIN(ctid) 
    FROM tag 
    GROUP BY id
);

-- Show remaining records
SELECT COUNT(*) as total_tags FROM tag;