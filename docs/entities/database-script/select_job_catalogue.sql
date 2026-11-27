-- Job counts and the latest successful refresh for each registered source.
SELECT
    s.provider,
    s.data_status,
    s.state AS source_state,
    COUNT(p.id) AS total_jobs,
    COUNT(CASE
        WHEN p.status = 'active'
            AND (p.expires_at IS NULL OR julianday(p.expires_at) > julianday('now'))
        THEN 1
    END) AS active_jobs,
    s.last_fetched_at AS last_fetch_utc
FROM job_source AS s
LEFT JOIN job_posting AS p
    ON p.provider = s.provider AND p.map_group = 'job'
GROUP BY s.provider, s.data_status, s.state, s.last_fetched_at
ORDER BY s.data_status = 'mock', s.provider;

-- The two most recently updated postings per source, including their original links.
WITH ranked_jobs AS (
    SELECT
        p.provider,
        s.data_status,
        p.status,
        p.title,
        p.organization,
        p.source_url,
        ROW_NUMBER() OVER (
            PARTITION BY p.provider
            ORDER BY COALESCE(p.updated_at, p.posted_at, p.fetched_at) DESC, p.id
        ) AS row_number
    FROM job_posting AS p
    JOIN job_source AS s ON s.provider = p.provider
    WHERE p.map_group = 'job'
)
SELECT provider, data_status, status, title, organization, source_url
FROM ranked_jobs
WHERE row_number <= 2
ORDER BY data_status = 'mock', provider, row_number;
