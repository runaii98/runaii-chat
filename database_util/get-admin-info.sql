-- Get user information including admin accounts
SELECT id, name, email, role, created_at 
FROM "user" 
ORDER BY created_at;

-- Also check auth table for additional details
SELECT id, email, password, active
FROM "auth"
ORDER BY id;