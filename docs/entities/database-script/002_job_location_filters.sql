-- Run once after 001 on an existing catalogue. The Backend applies this on open.
ALTER TABLE job_posting ADD COLUMN province TEXT;
ALTER TABLE job_posting ADD COLUMN district TEXT;
ALTER TABLE job_posting ADD COLUMN work_mode TEXT CHECK (work_mode IN ('onsite', 'hybrid', 'remote'));
