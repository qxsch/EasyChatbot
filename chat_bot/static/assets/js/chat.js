function getPageNumberArrayAsString(pages) {
    var a = [];
    for(var i = 0; i < pages.length; i++) {
        a.push(parseInt(pages[i]) + 1);
    }
    return a.join(", ");
}

class MarkdownRenderer {
    #mdElement = null;
    #mdPrependContent = "";
    #mdAppendContent = "";
    #mdContent = "";
    constructor(mdElement, mdPrependContent = "", mdContent = "", mdAppendContent = "") {
        this.#mdElement = mdElement;
        this.#mdPrependContent = String(mdPrependContent);
        if(mdContent !== undefined && mdContent !== null) {
            this.#mdContent = String(mdContent);
        }
        this.#mdAppendContent = String(mdAppendContent);
    }

    getContent() {
        return this.#mdContent;
    }

    addContent(content) {
        if(content === undefined || content === null) {
            return;
        }
        this.#mdContent += String(content);
        this.renderMarkdown();
        return;
    }

    renderMarkdown() {
        this.#mdElement.innerHTML = [
            this.#mdPrependContent,
            this.#mdContent,
            this.#mdAppendContent,
            ""
        ].join("\n");
        return;
    }
}


class ChatManager {
    #submitBtn = null;
    #clearBtn = null;
    #chatTextBox = null;
    #chatBubblesContainer = null;
    #chatMessages = [];
    #restorePromptOnFailure = true;
    #streaming = true;
    #submitting = false;

    constructor(
        streaming = null,
        restorePromptOnFailure = true,
        submitBtn = null,
        clearBtn = null,
        chatTextBox = null,
        chatBubblesContainer = null
    ) {
        if(streaming === null) {
            if(window.chatbot_configuration && "streaming" in window.chatbot_configuration) {
                this.#streaming = Boolean(window.chatbot_configuration.streaming);
            }
            else {
                this.#streaming = true;
            }
        }
        else {
            this.#streaming = Boolean(streaming);
        }
        console.log("Chatbot Streaming", this.#streaming);
        this.#submitBtn = this.#getHtmlElement(submitBtn, "chatSubmitBtn");
        this.#clearBtn = this.#getHtmlElement(clearBtn, "chatClearBtn");
        this.#chatTextBox = this.#getHtmlElement(chatTextBox, "chatTextBox");
        this.#chatBubblesContainer = this.#getHtmlElement(chatBubblesContainer, "chatBubblesContainer");

        this.#chatTextBox.addEventListener("keydown", this.#onChatTextBoxKeyDown.bind(this));
        this.#submitBtn.addEventListener("click", this.submitMessage.bind(this));
        this.#clearBtn.addEventListener("click", this.clearChat.bind(this));

        this.setRestorePromptOnFailure(restorePromptOnFailure);
    }

    #onChatTextBoxKeyDown(event) {
        // check if the key is enter and not shift+enter (to allow multiline messages)
        if(event.key === "Enter" && !event.shiftKey) {
            event.preventDefault();
            this.#submitBtn.click();
        }
    }

    #getHtmlElement(element, defaultValue = "") {
        if(element === undefined || element === null || element === "") {
            element = String(defaultValue);
        }
        if(typeof element === "string") {
            if(element.trim() != "") {
                element = document.getElementById(element);
            }
            else {
                element = null;
            }
        }
        if(!(element instanceof HTMLElement)) {
            throw new Error("element must be an HTMLElement or string with the id of the element");
        }
        return element;
    }

    getRestorePromptOnFailure() {
        return this.#restorePromptOnFailure;
    }
    setRestorePromptOnFailure(value) {
        this.#restorePromptOnFailure = Boolean(value);
        return this;
    }

    #removeUiWaitingChatMessage(messageElement) {
        // remove the waiting messages
        while(
            this.#chatBubblesContainer.lastChild !== null &&
            this.#chatBubblesContainer.lastChild.classList.contains("waiting")
        ) {
            this.#chatBubblesContainer.removeChild(this.#chatBubblesContainer.lastChild);
        }
    }
    #addUiWaitingChatMessage() {
        var messageElement = document.createElement("div");
        messageElement.classList.add("chatMessage");
        messageElement.classList.add("assistant");
        messageElement.classList.add("waiting");
        messageElement.innerHTML = '<div class="dot-pulse"></div>';
        this.#chatBubblesContainer.appendChild(messageElement);
        return;
    }

    #addUiChatMessage(message, role, pushToHistory, addtionalClasses = []) {
        if(pushToHistory && role !== "error") {
            this.#chatMessages.push({
                "role": role,
                "content": message
            });
        }
        this.#removeUiWaitingChatMessage();

        var messageElement = document.createElement("div");
        messageElement.classList.add("chatMessage");
        messageElement.classList.add(role);
        for (var i = 0; i < addtionalClasses.length; i++) {
            messageElement.classList.add(addtionalClasses[i]);
        }
        messageElement.innerText = message;
        this.#chatBubblesContainer.appendChild(messageElement);
        return;
    }

    #addUiUserChatMessage(message) {
        this.#addUiChatMessage(message, "user", true);
        this.#addUiWaitingChatMessage();
        this.#scrollToBottom();
        return;
    }
    
    #addUiErrorChatMessage(message) {
        this.#addUiChatMessage(message, "error", false);
        this.#scrollToBottom();
        return;
    }

    #popLastChatMessage() {
        this.#removeUiWaitingChatMessage();
        this.#chatMessages.pop();
        this.#chatBubblesContainer.removeChild(this.#chatBubblesContainer.lastChild);
        return;
    }

    async clearChat() {
        this.#chatMessages = [];
        this.#chatBubblesContainer.innerHTML = "";
        this.#submitting = false;
        try {
            window.pdfRenderer.clearCache();
        }
        catch(e) {
            console.error("Error while clearing cache", e);
        }
        return;
    }


    async #fetchFromStreamingApi(message) {
        const selectedChoice = 0;
        let mdRenderer = null;

        const response = await fetch("/api/chat/stream", {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                "messages": this.#chatMessages
            })
        });
        const reader = response.body.getReader();
        const decoder = new TextDecoder("utf-8");
        let { value: chunk, done: readerDone } = await reader.read();
        let buffer = "";

        try {
            while(!readerDone) {
                buffer += decoder.decode(chunk, { stream: true });
                let lines = buffer.split("\n");
                buffer = lines.pop(); // keep the last (partial) line in the buffer

                if(lines.length > 0) {
                    if(mdRenderer === null) {
                        // we have no renderer, so we need to create the renderer and process the first choice (with citations)
                        while(lines.length > 0) {
                            let line = lines.shift().trim();
                            if(line != "") {
                                var data = JSON.parse(line);
                                if(data === undefined || data === null || "error" in data) {
                                    console.log("JSON Data", data);
                                    throw new Error("Received invalid response");
                                }
                                if(!("choices" in data)) {
                                    console.log("JSON Data", data);
                                    throw new Error("Response does not contain choices");
                                }
                                mdRenderer = await this.#processChoice(data.choices[selectedChoice]);
                                break;
                            }
                        }
                    }
                    // we have a renderer, so we need to merge the content
                    let mergedContent = "";
                    while(lines.length > 0) {
                        let line = lines.shift().trim();
                        if(line != "") {
                            var data = JSON.parse(line);
                            if(data === undefined || data === null || "error" in data) {
                                console.log("JSON Data", data);
                                throw new Error("Received invalid response");
                            }
                            if(!("choices" in data)) {
                                console.log("JSON Data", data);
                                throw new Error("Response does not contain choices");
                            }
                            if(data.choices[selectedChoice].delta.content !== undefined && data.choices[selectedChoice].delta.content !== null) {
                                mergedContent += String(data.choices[selectedChoice].delta.content);
                            }
                        }
                    }
                    if(mergedContent != "") {
                        mdRenderer.addContent(mergedContent);
                    }
                }
                ({ value: chunk, done: readerDone } = await reader.read());
            }
            buffer = buffer.trim();
            if(buffer != "") {
                console.log("Buffer", buffer);
                var data = JSON.parse(line);
                if(data === undefined || data === null || "error" in data) {
                    console.log("JSON Data", data);
                    throw new Error("Received invalid response");
                }
                if(!("choices" in data)) {
                    console.log("JSON Data", data);
                    throw new Error("Response does not contain choices");
                }
                if(data.choices[selectedChoice].delta.content !== undefined && data.choices[selectedChoice].delta.content !== null) {
                    mdRenderer.addContent(data.choices[selectedChoice].delta.content);
                }
            }
        }
        catch(e) {
            console.error("Error while processing choice", e);
            return false;
        }

        this.#chatMessages.pop();
        this.#chatMessages.push({
            "role": "assistant",
            "content": mdRenderer.getContent()
        });

        if(mdRenderer !== null) {
            window.setTimeout(function() {
                mdRenderer.addContent("\n");
            }, 50);
        }
        this.#scrollToBottom();

        return true;
    }

    async #fetchFromDefaultApi(message) {
        const response = await fetch("/api/chat", {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                "messages": this.#chatMessages
            })
        });
        if(response.status != 200) {
            console.log("Received unexpected status", response.status);
        }
        var data = await response.json();
        // check if the response is valid
        if(data === undefined || data === null || "error" in data) {
            console.log("JSON Data", data);
            throw new Error("Received invalid response");
        }
        if(!("choices" in data)) {
            console.log("JSON Data", data);
            throw new Error("Response does not contain choices");
        }
        if(data.choices.length > 1) {
            console.log("JSON Data contains multiple choices", data);
        }
        const selectedChoice = 0;
        try {
            await this.#processChoice(data.choices[selectedChoice]);
        }
        catch(e) {
            console.error("Error while processing choice", e);
            return false;
        }
        return true;
    }

    async submitMessage() {
        // still chatting
        if(this.#submitting) {
            return;
        }
        this.#submitting = true;
        var message = this.#chatTextBox.value;
        if(typeof message !== "string") {
            return;
        }
        message = message.trim();
        if(message === "") {
            return;
        }
        // from here on, we have a valid message
        this.#addUiUserChatMessage(message);
        this.#chatTextBox.value = "";

        try {
            if(this.#streaming) {
                await this.#fetchFromStreamingApi(message);
            }
            else {
                await this.#fetchFromDefaultApi(message);
            }
        }
        catch(e) {
            if(this.#restorePromptOnFailure) {
                this.#popLastChatMessage()
                this.#chatTextBox.value = message;
            }
            this.#addUiErrorChatMessage("Error while sending message");
            console.error("Error while sending message", e);
            return;
        }
        finally {
            this.#submitting  = false;
        }
        return;
    }

    async #processChoice(choice) {
        this.#removeUiWaitingChatMessage();
        if((choice.delta !== undefined && choice.delta !== null)
            && (choice.message === undefined || choice.message === null)) {
            choice.message = choice.delta;
        }

        this.#chatMessages.push({
            "role": "assistant",
            "content": String(choice.message.content)
        });

        var appendContent = "\n\n";
        for(var i = 0; i < choice.message.context.citations.length; i++) {
            appendContent += "[doc" + (i + 1) + "]: " + "https://easy-chat-bot/citation/" + i + "\n";
        }
        
        var messageElement = document.createElement("div");
        messageElement.classList.add("chatMessage");
        messageElement.classList.add("assistant");
        // adding markdown
        var zmd = document.createElement("zero-md");
        zmd.addEventListener('zero-md-rendered', function() {
            console.log("configuring markdown links");
            var nodes = zmd.shadowRoot.querySelectorAll('a[href]');
            var currentUrl = new URL(window.location.href);
            nodes.forEach(function(node) {
                var href = new URL(node.href);
                if (href.host === "easy-chat-bot") {
                    if(href.pathname.startsWith("/citation/")) {                        
                        const citationIndex = parseInt(href.pathname.substring(10));
                        const citation = choice.message.context.citations[citationIndex];
                        node.href="#";
                        node.classList.add("easychatbotcitation");
                        node.innerText = (citationIndex + 1);
                        node.title = citation.title;
                        //node.title = citation.storageaccount_blob;
                        if(citation.pages.length > 0) {
                            if(citation.pages.length == 1) {
                                node.title += " (page " + getPageNumberArrayAsString(citation.pages) + ")";
                            }
                            else {
                                node.title += " (pages " + getPageNumberArrayAsString(citation.pages) + ")";
                            }
                        }
                        if(citation.url.endsWith(".pdf")) {
                            node.addEventListener("click", function(event) {
                                event.preventDefault();
                                console.log("PDF Citation", citation);
                                window.pdfRenderer.renderPDF(citation);
                            });
                        }
                    }
                }
                else if(href.host !== currentUrl.host) {
                    // external link
                    node.target = "_blank";
                    return;
                }
            });
        });
        zmd.innerHTML = [
            '<template data-append>',
            '<link rel="stylesheet" href="/static/assets/css/zmd.css">',
            '<style>',
            ' :root {color-scheme: only light;}',
            ' .markdown-body { background-color:transparent; min-height: 10px;} ',
            '</style>',
            '</template>'
        ].join('\n');
        var md = document.createElement("script");
        md.type = "text/markdown";
        if(choice.message.content === undefined || choice.message.content === null) {
            md.innerHTML = "";
        }
        else {
            md.innerHTML = choice.message.content + appendContent + "\n";
        }
        zmd.appendChild(md);
        messageElement.appendChild(zmd);

        var citationBox = document.createElement("div");
        citationBox.classList.add("citationBox");
        citationBox.innerHTML = "<b>Citations:</b>";
        // Citation links
        for(var i = 0; i < choice.message.context.citations.length; i++) {
            const citation = choice.message.context.citations[i];
            const citationElement = document.createElement("a");
            citationElement.href = "#";
            citationElement.innerText = "doc" + (i + 1);
            citationElement.title = citation.title;
            if(citation.pages.length > 0) {
                if(citation.pages.length == 1) {
                    citationElement.title  += " (page " + getPageNumberArrayAsString(citation.pages) + ")";
                }
                else {
                    citationElement.title  += " (pages " + getPageNumberArrayAsString(citation.pages) + ")";
                }
            }
            citationElement.innerText = citationElement.title
            const numEl = document.createElement("span")
            numEl.innerText = (i + 1);
            citationElement.prepend(numEl);

            if(citation.url.endsWith(".pdf")) {
                citationElement.addEventListener("click", function(event) {
                    event.preventDefault();
                    console.log("Citation", citation);
                    window.pdfRenderer.renderPDF(citation);
                });
                citationBox.appendChild(citationElement);
            }
        }
        messageElement.appendChild(citationBox);
        
        this.#chatBubblesContainer.appendChild(messageElement);
        this.#scrollToBottom();
        return new MarkdownRenderer(md, "", choice.message.content, appendContent);
    }

    #scrollToBottom() {
        const el = this.#chatBubblesContainer;
        window.setTimeout(function() {
            if(el.lastChild !== null) {
                el.lastChild.scrollIntoView({behavior: "smooth", block: "start", inline: "nearest"});
            }
        }, 100);
        return;
    }
}


window.chatbot = new ChatManager();  // enable streaming
// window.chatbot = new ChatManager(false);  // disable streaming
