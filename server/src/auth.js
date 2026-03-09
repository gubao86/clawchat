import jwt from 'jsonwebtoken';
import config from './config.js';

export function signToken(payload) {
  return jwt.sign(payload, config.jwtSecret, { expiresIn: config.jwtExpiry });
}

export function verifyToken(token) {
  return jwt.verify(token, config.jwtSecret);
}

export function authMiddleware(req, res, next) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) return res.status(401).json({ error: 'No token' });
  try {
    req.user = verifyToken(header.slice(7));
    next();
  } catch {
    res.status(401).json({ error: 'Invalid token' });
  }
}
