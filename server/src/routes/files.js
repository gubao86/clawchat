import { Router } from 'express';
import multer from 'multer';
import { v4 as uuid } from 'uuid';
import { join, extname } from 'path';
import { existsSync, mkdirSync } from 'fs';
import { authMiddleware } from '../auth.js';
import config from '../config.js';

const router = Router();
mkdirSync(config.uploads, { recursive: true });

const ALLOWED_TYPES = new Set([
  'image/jpeg', 'image/png', 'image/gif', 'image/webp',
  'audio/ogg', 'audio/mpeg', 'audio/wav', 'audio/mp4', 'audio/webm',
  'video/mp4', 'video/webm',
  'application/pdf', 'text/plain',
]);

const storage = multer.diskStorage({
  destination: config.uploads,
  filename: (req, file, cb) => {
    const ext = extname(file.originalname) || '';
    cb(null, `${uuid()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: config.maxFileSize },
  fileFilter: (req, file, cb) => {
    cb(null, ALLOWED_TYPES.has(file.mimetype));
  },
});

router.post('/upload', authMiddleware, upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No valid file' });
  res.json({ ok: true, file: { id: req.file.filename, name: req.file.originalname, size: req.file.size, type: req.file.mimetype, url: `/files/${req.file.filename}` } });
});

router.get('/:fileId', authMiddleware, (req, res) => {
  const filePath = join(config.uploads, req.params.fileId);
  if (!filePath.startsWith(config.uploads)) return res.status(403).json({ error: 'Forbidden' });
  if (!existsSync(filePath)) return res.status(404).json({ error: 'Not found' });
  res.sendFile(filePath);
});

export default router;
