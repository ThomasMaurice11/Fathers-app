-- ============================================================
-- 000010: Seed predefined stages
-- ============================================================

insert into public.stages (id, name) values
  (1,  'KG1'),
  (2,  'KG2'),
  (3,  'Grade 1'),
  (4,  'Grade 2'),
  (5,  'Grade 3'),
  (6,  'Grade 4'),
  (7,  'Grade 5'),
  (8,  'Grade 6'),
  (9,  '1st Prep'),
  (10, '2nd Prep'),
  (11, '3rd Prep'),
  (12, '1st Sec'),
  (13, '2nd Sec'),
  (14, '3rd Sec'),
  (15, '1st University'),
  (16, '2nd University'),
  (17, '3rd University'),
  (18, '4th University'),
  (19, 'Graduated')
on conflict (id) do update set name = excluded.name;
