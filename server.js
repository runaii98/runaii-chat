const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const { WebSocketServer } = require('ws');
const http = require('http');
const path = require('path');
require('dotenv').config();

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.static(path.join(__dirname, 'public')));

// Basic routes
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/api/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    models: ['gpt-3.5-turbo', 'gpt-4', 'claude-3-sonnet', 'gemini-pro']
  });
});

// AI Chat endpoint
app.post('/api/chat', async (req, res) => {
  try {
    const { message, model = 'gpt-3.5-turbo', chatHistory = [] } = req.body;
    
    if (!message) {
      return res.status(400).json({ error: 'Message is required' });
    }

    // Mock response for now - will integrate real AI APIs
    const mockResponse = {
      id: Date.now().toString(),
      model: model,
      message: `This is a mock response from ${model}. You said: "${message}". 
      
Real AI integration coming soon! Your startup will support:
- OpenAI GPT models
- Anthropic Claude
- Google Gemini
- Custom models`,
      timestamp: new Date().toISOString(),
      usage: {
        promptTokens: message.length,
        completionTokens: 150,
        totalTokens: message.length + 150
      }
    };

    res.json(mockResponse);
  } catch (error) {
    console.error('Chat error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// WebSocket for real-time features
wss.on('connection', (ws) => {
  console.log('Client connected');
  
  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data);
      console.log('Received:', message);
      
      // Echo back for now
      ws.send(JSON.stringify({
        type: 'response',
        data: `Server received: ${message.content}`
      }));
    } catch (error) {
      console.error('WebSocket error:', error);
    }
  });
  
  ws.on('close', () => {
    console.log('Client disconnected');
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`🚀 RunAI Chat Server running on port ${PORT}`);
  console.log(`📱 Access your app at: http://localhost:${PORT}`);
  console.log(`🔧 Environment: ${process.env.NODE_ENV || 'development'}`);
});