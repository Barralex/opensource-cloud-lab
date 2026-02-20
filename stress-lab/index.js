import Fastify from 'fastify'
import pg from 'pg'
import { S3Client, PutObjectCommand, GetObjectCommand, ListObjectsV2Command } from '@aws-sdk/client-s3'

const app = Fastify()
const POD = process.env.HOSTNAME || 'local'

// DB & S3
const db = new pg.Pool({ connectionString: process.env.DATABASE_URL })
const s3 = new S3Client({
  endpoint: `http://${process.env.MINIO_HOST || 'localhost'}:9000`,
  credentials: { accessKeyId: process.env.MINIO_ACCESS_KEY || 'admin', secretAccessKey: process.env.MINIO_SECRET_KEY || 'admin' },
  region: 'us-east-1',
  forcePathStyle: true,
})

app.get('/', async () => ({ status: 'ok', pod: POD, timestamp: new Date().toISOString() }))
app.get('/health', async () => ({ status: 'healthy', pod: POD }))
app.get('/metrics', async () => ({ pod: POD, memory_mb: Math.round(process.memoryUsage().heapUsed / 1048576), uptime_s: Math.round(process.uptime()) }))

app.get('/cpu/:ms', async (req) => {
  const ms = +req.params.ms, start = Date.now()
  while (Date.now() - start < ms) Math.sqrt(Math.random())
  return { pod: POD, operation: 'cpu_burn', requested_ms: ms, actual_ms: Date.now() - start }
})

app.get('/db/:n', async (req) => {
  const n = +req.params.n, start = Date.now()
  for (let i = 0; i < n; i++) await db.query('SELECT $1::int, random()', [i])
  return { pod: POD, operation: 'db_queries', queries: n, total_ms: Date.now() - start }
})

app.get('/memory/:mb', async (req) => {
  Buffer.alloc(+req.params.mb * 1048576)
  return { pod: POD, operation: 'memory_alloc', allocated_mb: +req.params.mb }
})

app.get('/sleep/:ms', async (req) => {
  await new Promise(r => setTimeout(r, +req.params.ms))
  return { pod: POD, operation: 'sleep', slept_ms: +req.params.ms }
})

app.post('/upload/:filename', { bodyLimit: 10485760 }, async (req) => {
  const body = Buffer.from(await req.body)
  await s3.send(new PutObjectCommand({ Bucket: 'stress-lab', Key: req.params.filename, Body: body }))
  return { pod: POD, operation: 'upload', filename: req.params.filename, size: body.length }
})

app.get('/download/:filename', async (req, reply) => {
  const data = await s3.send(new GetObjectCommand({ Bucket: 'stress-lab', Key: req.params.filename }))
  return reply.header('x-pod', POD).send(Buffer.from(await data.Body.transformToByteArray()))
})

app.get('/files', async () => {
  const data = await s3.send(new ListObjectsV2Command({ Bucket: 'stress-lab' }))
  return { pod: POD, files: (data.Contents || []).map(f => ({ name: f.Key, size: f.Size })) }
})

// Infrastructure diagram
import { readFileSync } from 'fs'
app.get('/diagram', async (req, reply) => {
  const html = readFileSync('/app/infra-status.html', 'utf8')
  return reply.type('text/html').send(html)
})

app.listen({ port: process.env.PORT || 4000, host: '0.0.0.0' })
