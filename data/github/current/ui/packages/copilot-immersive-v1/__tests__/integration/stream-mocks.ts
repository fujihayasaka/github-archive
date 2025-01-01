import {makeGate, type TestMessageStream} from '@github-ui/copilot-chat/test-utils/mock-streaming'

// creation instructions in FileGeneration.test.tsx
export const getGenerationStream = (): TestMessageStream => [
  {
    type: 'content',
    body: 'Here is a simple calculator using HTML, CSS, and JavaScript:\n\n',
  },
  {
    type: 'content',
    body: '````html name=index.html\n',
  },
  {
    type: 'content',
    body: '<!DOCTYPE html>\n',
  },
  {
    type: 'content',
    body: '<html lang="en">\n',
  },
  makeGate('index.html streaming started'),
  {
    type: 'content',
    body: '<head>\n',
  },
  {
    type: 'content',
    body: '    <meta charset="UTF-8">\n',
  },
  {
    type: 'content',
    body: '    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n',
  },
  {
    type: 'content',
    body: '    <title>Simple Calculator</title>\n',
  },
  {
    type: 'content',
    body: '    <link rel="stylesheet" href="styles.css">\n',
  },
  {
    type: 'content',
    body: '</head>\n',
  },
  {
    type: 'content',
    body: '<body>\n',
  },
  {
    type: 'content',
    body: '    <div class="calculator">\n',
  },
  {
    type: 'content',
    body: '        <input type="text" class="calculator-screen" value="" disabled />\n',
  },
  {
    type: 'content',
    body: '        <div class="calculator-keys">\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="operator" value="+">+</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="operator" value="-">-</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="operator" value="*">&times;</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="operator" value="/">&divide;</button>\n\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="7">7</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="8">8</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="9">9</button>\n\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="4">4</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="5">5</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="6">6</button>\n\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="1">1</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="2">2</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="3">3</button>\n\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="0">0</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="decimal" value=".">.</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="all-clear" value="all-clear">AC</button>\n\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="equal-sign" value="=">=</button>\n',
  },
  {
    type: 'content',
    body: '        </div>\n',
  },
  {
    type: 'content',
    body: '    </div>\n',
  },
  {
    type: 'content',
    body: '    <script src="script.js"></script>\n',
  },
  {
    type: 'content',
    body: '</body>\n',
  },
  {
    type: 'content',
    body: '</html>\n',
  },
  {
    type: 'content',
    body: '````\n\n',
  },
  {
    type: 'content',
    body: '````css name=styles.css\n',
  },
  {
    type: 'content',
    body: 'body {\n',
  },
  {
    type: 'content',
    body: "    font-family: 'Arial', sans-serif;\n",
  },
  makeGate('styles.css streaming started'),
  {
    type: 'content',
    body: '    display: flex;\n',
  },
  {
    type: 'content',
    body: '    justify-content: center;\n',
  },
  {
    type: 'content',
    body: '    align-items: center;\n',
  },
  {
    type: 'content',
    body: '    height: 100vh;\n',
  },
  {
    type: 'content',
    body: '    background-color: #f4f4f4;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: '.calculator {\n',
  },
  {
    type: 'content',
    body: '    border-radius: 5px;\n',
  },
  {
    type: 'content',
    body: '    box-shadow: 0px 0px 20px 0px rgba(0, 0, 0, 0.2);\n',
  },
  {
    type: 'content',
    body: '    padding: 20px;\n',
  },
  {
    type: 'content',
    body: '    background-color: #fff;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: '.calculator-screen {\n',
  },
  {
    type: 'content',
    body: '    width: 100%;\n',
  },
  {
    type: 'content',
    body: '    height: 80px;\n',
  },
  {
    type: 'content',
    body: '    border: none;\n',
  },
  {
    type: 'content',
    body: '    background-color: #252525;\n',
  },
  {
    type: 'content',
    body: '    color: #fff;\n',
  },
  {
    type: 'content',
    body: '    text-align: right;\n',
  },
  {
    type: 'content',
    body: '    padding-right: 20px;\n',
  },
  {
    type: 'content',
    body: '    padding-left: 10px;\n',
  },
  {
    type: 'content',
    body: '    font-size: 2.5em;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: 'button {\n',
  },
  {
    type: 'content',
    body: '    height: 60px;\n',
  },
  {
    type: 'content',
    body: '    font-size: 2em;\n',
  },
  {
    type: 'content',
    body: '    width: 25%;\n',
  },
  {
    type: 'content',
    body: '    background-color: #e0e0e0;\n',
  },
  {
    type: 'content',
    body: '    border: none;\n',
  },
  {
    type: 'content',
    body: '    float: left;\n',
  },
  {
    type: 'content',
    body: '    outline: none;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: 'button:hover {\n',
  },
  {
    type: 'content',
    body: '    background-color: #d4d4d4;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: '.operator {\n',
  },
  {
    type: 'content',
    body: '    background-color: #ff9500;\n',
  },
  {
    type: 'content',
    body: '    color: #fff;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: '.operator:hover {\n',
  },
  {
    type: 'content',
    body: '    background-color: #e08d00;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: '.equal-sign {\n',
  },
  {
    type: 'content',
    body: '    background-color: #ff9500;\n',
  },
  {
    type: 'content',
    body: '    color: #fff;\n',
  },
  {
    type: 'content',
    body: '    height: calc(100% - 130px);\n',
  },
  {
    type: 'content',
    body: '    float: right;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: '.equal-sign:hover {\n',
  },
  {
    type: 'content',
    body: '    background-color: #e08d00;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: '.all-clear {\n',
  },
  {
    type: 'content',
    body: '    background-color: #ff3b30;\n',
  },
  {
    type: 'content',
    body: '    color: #fff;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: '.all-clear:hover {\n',
  },
  {
    type: 'content',
    body: '    background-color: #e02b20;\n',
  },
  {
    type: 'content',
    body: '}\n',
  },
  {
    type: 'content',
    body: '````\n\n',
  },
  {
    type: 'content',
    body: '````javascript name=script.js\n',
  },
  {
    type: 'content',
    body: 'const calculator = {\n',
  },
  {
    type: 'content',
    body: "    displayValue: '0',\n",
  },
  {
    type: 'content',
    body: '    firstOperand: null,\n',
  },
  {
    type: 'content',
    body: '    waitingForSecondOperand: false,\n',
  },
  {
    type: 'content',
    body: '    operator: null,\n',
  },
  {
    type: 'content',
    body: '};\n\n',
  },
  {
    type: 'content',
    body: 'function inputDigit(digit) {\n',
  },
  {
    type: 'content',
    body: '    const { displayValue, waitingForSecondOperand } = calculator;\n\n',
  },
  {
    type: 'content',
    body: '    if (waitingForSecondOperand === true) {\n',
  },
  {
    type: 'content',
    body: '        calculator.displayValue = digit;\n',
  },
  {
    type: 'content',
    body: '        calculator.waitingForSecondOperand = false;\n',
  },
  {
    type: 'content',
    body: '    } else {\n',
  },
  {
    type: 'content',
    body: "        calculator.displayValue = displayValue === '0' ? digit : displayValue + digit;\n",
  },
  {
    type: 'content',
    body: '    }\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: 'function inputDecimal(dot) {\n',
  },
  {
    type: 'content',
    body: '    if (calculator.waitingForSecondOperand === true) return;\n\n',
  },
  {
    type: 'content',
    body: '    if (!calculator.displayValue.includes(dot)) {\n',
  },
  {
    type: 'content',
    body: '        calculator.displayValue += dot;\n',
  },
  {
    type: 'content',
    body: '    }\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: 'function handleOperator(nextOperator) {\n',
  },
  {
    type: 'content',
    body: '    const { firstOperand, displayValue, operator } = calculator;\n',
  },
  {
    type: 'content',
    body: '    const inputValue = parseFloat(displayValue);\n\n',
  },
  {
    type: 'content',
    body: '    if (operator && calculator.waitingForSecondOperand) {\n',
  },
  {
    type: 'content',
    body: '        calculator.operator = nextOperator;\n',
  },
  {
    type: 'content',
    body: '        return;\n',
  },
  {
    type: 'content',
    body: '    }\n\n',
  },
  {
    type: 'content',
    body: '    if (firstOperand == null && !isNaN(inputValue)) {\n',
  },
  {
    type: 'content',
    body: '        calculator.firstOperand = inputValue;\n',
  },
  {
    type: 'content',
    body: '    } else if (operator) {\n',
  },
  {
    type: 'content',
    body: '        const result = performCalculation[operator](firstOperand, inputValue);\n\n',
  },
  {
    type: 'content',
    body: '        calculator.displayValue = String(result);\n',
  },
  {
    type: 'content',
    body: '        calculator.firstOperand = result;\n',
  },
  {
    type: 'content',
    body: '    }\n\n',
  },
  {
    type: 'content',
    body: '    calculator.waitingForSecondOperand = true;\n',
  },
  {
    type: 'content',
    body: '    calculator.operator = nextOperator;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: 'const performCalculation = {\n',
  },
  {
    type: 'content',
    body: "    '/': (firstOperand, secondOperand) => firstOperand / secondOperand,\n\n",
  },
  {
    type: 'content',
    body: "    '*': (firstOperand, secondOperand) => firstOperand * secondOperand,\n\n",
  },
  {
    type: 'content',
    body: "    '+': (firstOperand, secondOperand) => firstOperand + secondOperand,\n\n",
  },
  {
    type: 'content',
    body: "    '-': (firstOperand, secondOperand) => firstOperand - secondOperand,\n\n",
  },
  {
    type: 'content',
    body: "    '=': (firstOperand, secondOperand) => secondOperand\n",
  },
  {
    type: 'content',
    body: '};\n\n',
  },
  {
    type: 'content',
    body: 'function resetCalculator() {\n',
  },
  {
    type: 'content',
    body: "    calculator.displayValue = '0';\n",
  },
  {
    type: 'content',
    body: '    calculator.firstOperand = null;\n',
  },
  {
    type: 'content',
    body: '    calculator.waitingForSecondOperand = false;\n',
  },
  {
    type: 'content',
    body: '    calculator.operator = null;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: 'function updateDisplay() {\n',
  },
  {
    type: 'content',
    body: "    const display = document.querySelector('.calculator-screen');\n",
  },
  {
    type: 'content',
    body: '    display.value = calculator.displayValue;\n',
  },
  {
    type: 'content',
    body: '}\n\n',
  },
  {
    type: 'content',
    body: 'updateDisplay();\n\n',
  },
  {
    type: 'content',
    body: "const keys = document.querySelector('.calculator-keys');\n",
  },
  {
    type: 'content',
    body: "keys.addEventListener('click', (event) => {\n",
  },
  {
    type: 'content',
    body: '    const { target } = event;\n',
  },
  {
    type: 'content',
    body: "    if (!target.matches('button')) {\n",
  },
  {
    type: 'content',
    body: '        return;\n',
  },
  {
    type: 'content',
    body: '    }\n\n',
  },
  {
    type: 'content',
    body: "    if (target.classList.contains('operator')) {\n",
  },
  {
    type: 'content',
    body: '        handleOperator(target.value);\n',
  },
  {
    type: 'content',
    body: '        updateDisplay();\n',
  },
  {
    type: 'content',
    body: '        return;\n',
  },
  {
    type: 'content',
    body: '    }\n\n',
  },
  {
    type: 'content',
    body: "    if (target.classList.contains('decimal')) {\n",
  },
  {
    type: 'content',
    body: '        inputDecimal(target.value);\n',
  },
  {
    type: 'content',
    body: '        updateDisplay();\n',
  },
  {
    type: 'content',
    body: '        return;\n',
  },
  {
    type: 'content',
    body: '    }\n\n',
  },
  {
    type: 'content',
    body: "    if (target.classList.contains('all-clear')) {\n",
  },
  {
    type: 'content',
    body: '        resetCalculator();\n',
  },
  {
    type: 'content',
    body: '        updateDisplay();\n',
  },
  {
    type: 'content',
    body: '        return;\n',
  },
  {
    type: 'content',
    body: '    }\n\n',
  },
  {
    type: 'content',
    body: '    inputDigit(target.value);\n',
  },
  {
    type: 'content',
    body: '    updateDisplay();\n',
  },
  {
    type: 'content',
    body: '});\n',
  },
  {
    type: 'content',
    body: '````\n\n',
  },
  {
    type: 'content',
    body: 'Save these files in the same directory and open `index.html` in a web browser to see the calculator in action.',
  },
  {
    type: 'droppedComponent',
    hasDroppedComponents: false,
  },
  {
    type: 'complete',
    id: '2ccc9b29-9843-4148-991f-fe27b0c6ad3a',
    parentMessageID: '91ad9bbe-94fb-46fc-815e-e55e6adda57b',
    model: '',
    turnId: '',
    createdAt: '2025-03-25T10:03:25.627661429-07:00',
    references: [],
    role: 'assistant',
    intent: 'conversation',
    copilotAnnotations: {
      CodeVulnerability: [],
      PublicCodeReference: [],
    },
  },
]

// creation instructions in FileGeneration.test.tsx
export const getEditStream = (): TestMessageStream => [
  {
    type: 'content',
    body: 'Here is the updated `index.html` file with the page title changed to "Calculator!":\n\n',
  },
  {
    type: 'content',
    body: '```html name=index.html\n',
  },
  {
    type: 'content',
    body: '<!DOCTYPE html>\n',
  },
  {
    type: 'content',
    body: '<html lang="en">\n',
  },
  makeGate('index.html streaming started'),
  {
    type: 'content',
    body: '<head>\n',
  },
  {
    type: 'content',
    body: '    <meta charset="UTF-8">\n',
  },
  {
    type: 'content',
    body: '    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n',
  },
  {
    type: 'content',
    body: '    <title>Calculator!</title>\n',
  },
  {
    type: 'content',
    body: '    <link rel="stylesheet" href="styles.css">\n',
  },
  {
    type: 'content',
    body: '</head>\n',
  },
  {
    type: 'content',
    body: '<body>\n',
  },
  {
    type: 'content',
    body: '    <div class="calculator">\n',
  },
  {
    type: 'content',
    body: '        <input type="text" class="calculator-screen" value="" disabled />\n',
  },
  {
    type: 'content',
    body: '        <div class="calculator-keys">\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="operator" value="+">+</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="operator" value="-">-</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="operator" value="*">&times;</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="operator" value="/">&divide;</button>\n\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="7">7</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="8">8</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="9">9</button>\n\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="4">4</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="5">5</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="6">6</button>\n\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="1">1</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="2">2</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="3">3</button>\n\n',
  },
  {
    type: 'content',
    body: '            <button type="button" value="0">0</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="decimal" value=".">.</button>\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="all-clear" value="all-clear">AC</button>\n\n',
  },
  {
    type: 'content',
    body: '            <button type="button" class="equal-sign" value="=">=</button>\n',
  },
  {
    type: 'content',
    body: '        </div>\n',
  },
  {
    type: 'content',
    body: '    </div>\n',
  },
  {
    type: 'content',
    body: '    <script src="script.js"></script>\n',
  },
  {
    type: 'content',
    body: '</body>\n',
  },
  {
    type: 'content',
    body: '</html>\n',
  },
  {
    type: 'content',
    body: '```',
  },
  {
    type: 'droppedComponent',
    hasDroppedComponents: false,
  },
  {
    type: 'complete',
    id: '91dd4b21-01bf-4971-b019-aec304a592ee',
    parentMessageID: 'add9e2ec-4b68-4637-8432-544b2042a7e1',
    model: '',
    turnId: '',
    createdAt: '2025-03-25T10:06:33.139481437-07:00',
    references: [],
    role: 'assistant',
    intent: 'conversation',
    copilotAnnotations: {
      CodeVulnerability: [],
      PublicCodeReference: [],
    },
  },
]
